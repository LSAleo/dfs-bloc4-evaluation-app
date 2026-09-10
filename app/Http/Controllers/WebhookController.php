<?php

namespace App\Http\Controllers;

use App\Models\Intervention;
use App\Models\Ticket;
use App\Services\EventLogService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class WebhookController extends Controller
{
    public function __construct(private readonly EventLogService $eventLogService)
    {
    }

    public function handle(Request $request): JsonResponse
    {
        if ($request->getUser() !== config('services.webhook.basic_user')
            || $request->getPassword() !== config('services.webhook.basic_password')) {
            return response()->json(['message' => 'Unauthorized'], 401, [
                'WWW-Authenticate' => 'Basic realm="OpsTrack Webhook"',
            ]);
        }

        $payload = $request->validate([
            'ticket_reference' => ['required', 'string'],
            'status' => ['required', 'string'],
            'summary' => ['nullable', 'string'],
            'external_event_id' => ['nullable', 'string'],
        ]);

        $ticket = Ticket::query()->where('reference', $payload['ticket_reference'])->firstOrFail();

        $externalEventId = $payload['external_event_id'] ?? null;

        // Deduplication : un meme evenement externe (external_event_id) ne doit
        // creer qu'une seule intervention. Les webhooks etant souvent rejoues,
        // on renvoie l'intervention deja enregistree de maniere idempotente.
        if ($externalEventId !== null) {
            $existing = Intervention::query()
                ->where('external_event_id', $externalEventId)
                ->first();

            if ($existing !== null) {
                return response()->json([
                    'message' => 'Webhook already processed.',
                    'intervention_id' => $existing->id,
                ]);
            }
        }

        $intervention = Intervention::query()->create([
            'ticket_id' => $ticket->id,
            'scheduled_for' => now()->addHour(),
            'status' => $payload['status'],
            'summary' => $payload['summary'] ?? 'Webhook update received.',
            'external_event_id' => $externalEventId,
        ]);

        // Le ticket reflete le statut reellement transmis par le webhook,
        // au lieu d'etre force sur 'scheduled' (suppression de l'ecart
        // entre l'evenement externe et l'etat en base).
        $ticket->update(['status' => $payload['status']]);

        $this->eventLogService->record('webhook', 'intervention.synced', [
            'ticket_id' => $ticket->id,
            'intervention_id' => $intervention->id,
            'payload' => $payload,
        ]);

        return response()->json([
            'message' => 'Webhook processed.',
            'intervention_id' => $intervention->id,
        ]);
    }
}

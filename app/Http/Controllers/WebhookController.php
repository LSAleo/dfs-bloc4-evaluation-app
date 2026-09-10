<?php

namespace App\Http\Controllers;

use App\Models\Intervention;
use App\Models\Ticket;
use App\Services\EventLogService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

class WebhookController extends Controller
{
    /**
     * Statuts acceptes depuis l'exterieur. La valeur transmise est recopiee dans
     * `interventions.status` ET `tickets.status`, deux colonnes `varchar(20)` :
     * une liste blanche est donc necessaire, faute de quoi un appelant externe
     * peut ecrire une valeur arbitraire (le KPI `openTickets` compte tout statut
     * hors `resolved`/`closed`, un statut inconnu resterait donc « ouvert »
     * indefiniment) ou depasser 20 caracteres et provoquer une erreur SQL 22001.
     */
    private const ALLOWED_STATUSES = ['new', 'scheduled', 'in_progress', 'resolved', 'closed'];

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

        // Validation explicite plutot que $request->validate() : ce point d'entree
        // court-circuite le kernel HTTP (cf. public/hooks.php), donc l'exception
        // ValidationException n'y est pas convertie de maniere fiable en reponse
        // 422. On formule donc la reponse d'erreur soi-meme.
        $validator = Validator::make($request->all(), [
            'ticket_reference' => ['required', 'string', 'max:50'],
            'status' => ['required', 'string', Rule::in(self::ALLOWED_STATUSES)],
            'summary' => ['nullable', 'string', 'max:2000'],
            'external_event_id' => ['nullable', 'string', 'max:100'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'Invalid webhook payload.',
                'errors' => $validator->errors(),
            ], 422);
        }

        $payload = $validator->validated();

        // Meme raison : firstOrFail() leverait une ModelNotFoundException dont la
        // conversion en 404 depend du gestionnaire global, absent de ce chemin.
        $ticket = Ticket::query()->where('reference', $payload['ticket_reference'])->first();

        if ($ticket === null) {
            return response()->json([
                'message' => 'Unknown ticket reference.',
            ], 404);
        }

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

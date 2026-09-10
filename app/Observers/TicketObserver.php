<?php

namespace App\Observers;

use App\Models\Ticket;
use Illuminate\Support\Facades\Cache;

class TicketObserver
{
    /**
     * Invalide le cache des KPI du tableau de bord des qu'un ticket est
     * cree, modifie ou supprime, afin que les compteurs affiches restent
     * coherents avec l'etat reel des tickets.
     */
    public function saved(Ticket $ticket): void
    {
        $this->flushDashboardKpis();
    }

    public function deleted(Ticket $ticket): void
    {
        $this->flushDashboardKpis();
    }

    private function flushDashboardKpis(): void
    {
        Cache::forget('dashboard.kpis');
    }
}

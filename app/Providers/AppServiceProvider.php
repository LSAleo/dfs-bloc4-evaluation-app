<?php

namespace App\Providers;

use App\Models\Ticket;
use App\Observers\TicketObserver;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Invalide le cache des KPI du tableau de bord a chaque mutation de ticket.
        Ticket::observe(TicketObserver::class);
    }
}

<?php

namespace Tests\Feature;

use App\Models\ApiToken;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TicketSearchTest extends TestCase
{
    use RefreshDatabase;

    private function apiToken(): string
    {
        return ApiToken::query()->firstOrFail()->token;
    }

    /**
     * Non-regression : le filtre de priorite doit s'appliquer aussi aux
     * correspondances sur le titre. INC-240301 (priorite "critical") contient
     * "terminal" dans son titre ; filtre priority=medium -> il doit etre exclu.
     * Avec le groupement incorrect (bug), il fuyait malgre le filtre.
     */
    public function test_priority_filter_applies_to_title_search(): void
    {
        $this->seed();

        $response = $this->withToken($this->apiToken())
            ->getJson('/api/v1/tickets?search=terminal&priority=medium');

        $response->assertOk();
        $references = collect($response->json('data'))->pluck('reference');

        $this->assertFalse($references->contains('INC-240301'));
    }

    /**
     * Non-regression : une charge d'injection SQL ne doit ni provoquer d'erreur
     * ni transformer la requete (requete parametree). Le terme litteral ne
     * correspond a aucun ticket -> 0 resultat (et non "OR 1=1" -> tous).
     */
    public function test_search_is_safe_against_sql_injection(): void
    {
        $this->seed();

        $response = $this->withToken($this->apiToken())
            ->getJson('/api/v1/tickets?search='.urlencode("' OR '1'='1' -- "));

        $response->assertOk();
        $response->assertJsonStructure(['data']);
        $this->assertCount(0, $response->json('data'));
    }
}

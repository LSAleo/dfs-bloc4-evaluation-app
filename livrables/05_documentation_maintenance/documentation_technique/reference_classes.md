# Reference des classes — OpsTrack Field Service

> **Fichier genere. Ne pas editer a la main.**
> Produit par [`tools/generate-code-reference.php`](../../../tools/generate-code-reference.php)
> a partir du code source applicatif (`app`, `database/seeders`, `database/factories`), **hors dependances tierces**
> (`vendor/`, `node_modules/`). Regeneration : `php tools/generate-code-reference.php`.

Perimetre analyse : **22 fichiers PHP**, **22 classes/interfaces/traits/enums**, **31 methodes publiques**.

## Sommaire

- `App\Http\Controllers` — 3 element(s)
- `App\Http\Controllers\Api` — 3 element(s)
- `App\Http\Middleware` — 1 element(s)
- `App\Http\Requests` — 2 element(s)
- `App\Http\Resources` — 1 element(s)
- `App\Models` — 6 element(s)
- `App\Models\Mongo` — 1 element(s)
- `App\Providers` — 1 element(s)
- `App\Services` — 2 element(s)
- `Database\Factories` — 1 element(s)
- `Database\Seeders` — 1 element(s)

---

## `App\Http\Controllers`

### Class `Controller` *(abstraite)*

Source : `app/Http/Controllers/Controller.php`

*Aucune methode publique.*

### Class `DashboardController`

Source : `app/Http/Controllers/DashboardController.php`

| Methode publique | Description |
| --- | --- |
| `__invoke(): View` | — |

### Class `WebhookController`

Source : `app/Http/Controllers/WebhookController.php`

| Methode publique | Description |
| --- | --- |
| `handle(Request $request): JsonResponse` | — |

---

## `App\Http\Controllers\Api`

### Class `ExternalContextController`

Source : `app/Http/Controllers/Api/ExternalContextController.php`

| Methode publique | Description |
| --- | --- |
| `weather(Request $request): JsonResponse` | — |

### Class `TechnicianController`

Source : `app/Http/Controllers/Api/TechnicianController.php`

| Methode publique | Description |
| --- | --- |
| `index(): JsonResponse` | — |

### Class `TicketController`

Source : `app/Http/Controllers/Api/TicketController.php`

| Methode publique | Description |
| --- | --- |
| `index(Request $request)` | — |
| `store(StoreTicketRequest $request)` | — |
| `show(Ticket $ticket)` | — |
| `update(UpdateTicketRequest $request, Ticket $ticket)` | — |

---

## `App\Http\Middleware`

### Class `EnsureApiTokenIsValid`

Source : `app/Http/Middleware/EnsureApiTokenIsValid.php`

| Methode publique | Description |
| --- | --- |
| `handle(Request $request, Closure $next): Response` | Handle an incoming request. |

---

## `App\Http\Requests`

### Class `StoreTicketRequest`

Source : `app/Http/Requests/StoreTicketRequest.php`

| Methode publique | Description |
| --- | --- |
| `authorize(): bool` | Determine if the user is authorized to make this request. |
| `rules(): array` | Get the validation rules that apply to the request. |

### Class `UpdateTicketRequest`

Source : `app/Http/Requests/UpdateTicketRequest.php`

| Methode publique | Description |
| --- | --- |
| `authorize(): bool` | Determine if the user is authorized to make this request. |
| `rules(): array` | Get the validation rules that apply to the request. |

---

## `App\Http\Resources`

### Class `TicketResource`

Source : `app/Http/Resources/TicketResource.php`

| Methode publique | Description |
| --- | --- |
| `toArray(Request $request): array` | Transform the resource into an array. |

---

## `App\Models`

### Class `ApiToken`

Source : `app/Models/ApiToken.php`

*Aucune methode publique.*

### Class `Customer`

Source : `app/Models/Customer.php`

| Methode publique | Description |
| --- | --- |
| `sites()` | — |

### Class `Intervention`

Source : `app/Models/Intervention.php`

| Methode publique | Description |
| --- | --- |
| `ticket()` | — |

### Class `Site`

Source : `app/Models/Site.php`

| Methode publique | Description |
| --- | --- |
| `customer()` | — |
| `tickets()` | — |

### Class `Ticket`

Source : `app/Models/Ticket.php`

| Methode publique | Description |
| --- | --- |
| `site()` | — |
| `openedBy()` | — |
| `assignedTo()` | — |
| `interventions()` | — |

### Class `User`

Source : `app/Models/User.php`

| Methode publique | Description |
| --- | --- |
| `openedTickets()` | — |
| `assignedTickets()` | — |

---

## `App\Models\Mongo`

### Class `EventLog`

Source : `app/Models/Mongo/EventLog.php`

*Aucune methode publique.*

---

## `App\Providers`

### Class `AppServiceProvider`

Source : `app/Providers/AppServiceProvider.php`

| Methode publique | Description |
| --- | --- |
| `register(): void` | Register any application services. |
| `boot(): void` | Bootstrap any application services. |

---

## `App\Services`

### Class `EventLogService`

Source : `app/Services/EventLogService.php`

| Methode publique | Description |
| --- | --- |
| `record(string $channel, string $eventType, array $payload = [], string $severity = 'info'): void` | — |

### Class `PublicWeatherService`

Source : `app/Services/PublicWeatherService.php`

| Methode publique | Description |
| --- | --- |
| `currentForSite(Site $site): array` | — |

---

## `Database\Factories`

### Class `UserFactory`

Source : `database/factories/UserFactory.php`

| Methode publique | Description |
| --- | --- |
| `definition(): array` | Define the model's default state. |
| `unverified(): static` | Indicate that the model's email address should be unverified. |

---

## `Database\Seeders`

### Class `DatabaseSeeder`

Source : `database/seeders/DatabaseSeeder.php`

| Methode publique | Description |
| --- | --- |
| `run(): void` | Seed the application's database. |


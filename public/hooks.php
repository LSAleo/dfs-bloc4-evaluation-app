<?php

use App\Http\Controllers\WebhookController;
use Illuminate\Http\Request;

require __DIR__.'/../vendor/autoload.php';

$app = require_once __DIR__.'/../bootstrap/app.php';
$kernel = $app->make(Illuminate\Contracts\Http\Kernel::class);

// Amorce le framework (environnement, configuration, service providers) avant
// de resoudre le controleur. Sans cet amorçage, les helpers tels que config()
// echouent avec « Target class [config] does not exist » et le webhook renvoie 500.
$kernel->bootstrap();

$request = Request::capture();

// Lie la requete au conteneur : ce point d'entree court-circuite le kernel HTTP,
// or plusieurs composants (dont le rendu des erreurs) resolvent « request » via
// le conteneur. Sans ce binding, une erreur secondaire « Target class [request]
// does not exist » masque la reponse. Le controleur assure lui-meme son
// authentification HTTP Basic.
$app->instance('request', $request);

$response = $app->make(WebhookController::class)->handle($request);
$response->send();

$kernel->terminate($request, $response);

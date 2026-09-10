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
$response = $app->make(WebhookController::class)->handle($request);
$response->send();

$kernel->terminate($request, $response);

<?php
declare(strict_types=1);

use Google\Auth\Credentials\ServiceAccountCredentials;

function fcm_json_keyfile(): string {
    return __DIR__ . '/secrets/seguimientomapacnt-service-account.json';
}

function fcm_access_token(): string {
    $autoload = __DIR__ . '/vendor/autoload.php';
    if (!file_exists($autoload)) {
        throw new Exception("No existe {$autoload}. Ejecuta composer install en " . __DIR__);
    }
    require_once $autoload;

    $jsonKeyFile = fcm_json_keyfile();
    if (!file_exists($jsonKeyFile)) {
        throw new Exception("Service account no encontrado: {$jsonKeyFile}");
    }

    $scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

    $creds = new ServiceAccountCredentials($scopes, $jsonKeyFile);
    $token = $creds->fetchAuthToken();

    if (!isset($token['access_token'])) {
        throw new Exception('No se pudo obtener access_token de Google');
    }

    return $token['access_token'];
}

function fcm_project_id(): string {
    $jsonKeyFile = fcm_json_keyfile();

    if (!file_exists($jsonKeyFile)) {
        throw new Exception("Service account NO existe: {$jsonKeyFile}");
    }
    if (!is_readable($jsonKeyFile)) {
        throw new Exception("Service account existe pero NO es legible por PHP: {$jsonKeyFile}");
    }

    $raw = file_get_contents($jsonKeyFile);
    if ($raw === false || trim($raw) === '') {
        throw new Exception("No se pudo leer service account (vacío o error): {$jsonKeyFile}");
    }

    $j = json_decode($raw, true);
    if (!is_array($j)) {
        throw new Exception("Service account NO es JSON válido: {$jsonKeyFile}");
    }
    if (empty($j['project_id'])) {
        throw new Exception("project_id no encontrado en service account json");
    }
    return $j['project_id'];
}

function fcm_send_token(array $opts): array {
    $projectId = fcm_project_id();
    $token     = $opts['token'] ?? '';
    $title     = $opts['title'] ?? '';
    $body      = $opts['body'] ?? '';
    $data      = $opts['data'] ?? [];

    if ($token === '') throw new Exception("token vacío en fcm_send_token");

    $dataStr = [];
    foreach ($data as $k => $v) $dataStr[$k] = strval($v);

    $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";

    $payload = [
        'message' => [
            'token' => $token,
            'notification' => [
                'title' => $title,
                'body'  => $body,
            ],
            'data' => $dataStr,
            'android' => ['priority' => 'HIGH'],
        ],
    ];

    $accessToken = fcm_access_token();

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            "Authorization: Bearer {$accessToken}",
            "Content-Type: application/json; UTF-8",
        ],
        CURLOPT_POSTFIELDS => json_encode($payload),
        CURLOPT_TIMEOUT => 20,
    ]);

    $resp = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    // Intenta decodificar respuesta para verla “bonita” en Postman
    $decoded = json_decode((string)$resp, true);
    return ['code' => $code, 'resp_raw' => $resp, 'resp_json' => $decoded, 'err' => $err];
}

function fcm_send_topic(array $opts): array {
    $projectId = fcm_project_id();
    $topic     = $opts['topic'] ?? '';
    $title     = $opts['title'] ?? '';
    $body      = $opts['body'] ?? '';
    $data      = $opts['data'] ?? [];

    if ($topic === '') throw new Exception("topic vacío en fcm_send_topic");

    $dataStr = [];
    foreach ($data as $k => $v) $dataStr[$k] = strval($v);

    $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";

    $payload = [
        'message' => [
            'topic' => $topic,
            'notification' => [
                'title' => $title,
                'body'  => $body,
            ],
            'data' => $dataStr,
            'android' => [
  'priority' => 'HIGH',
  'notification' => [
    'channel_id' => 'tvc_noticias_high',
    'sound' => 'default',
  ],
],

        ],
    ];

    $accessToken = fcm_access_token();

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER => [
            "Authorization: Bearer {$accessToken}",
            "Content-Type: application/json; UTF-8",
        ],
        CURLOPT_POSTFIELDS => json_encode($payload),
    ]);

    $resp = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    return ['code' => $code, 'resp' => $resp, 'err' => $err];
}

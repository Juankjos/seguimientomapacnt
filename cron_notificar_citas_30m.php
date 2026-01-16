<?php
require 'config.php';

date_default_timezone_set('America/Mexico_City');

header('Content-Type: application/json; charset=utf-8');

// ==========================================================================================
// ========================= COLOCAR EN EL SERVIDOR PARA Noticias CNT =======================
// ==========================================================================================

function b64url($data) {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}

function get_access_token_from_sa($saPath) {
    if (!file_exists($saPath)) {
        throw new Exception("No existe service account: $saPath");
    }

    $sa = json_decode(file_get_contents($saPath), true);
    if (!$sa || empty($sa['client_email']) || empty($sa['private_key'])) {
        throw new Exception("Service account inválido");
    }

    $now = time();
    $header = ['alg' => 'RS256', 'typ' => 'JWT'];
    $claims = [
        'iss' => $sa['client_email'],
        'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
        'aud' => 'https://oauth2.googleapis.com/token',
        'iat' => $now,
        'exp' => $now + 3600,
    ];

    $jwtUnsigned = b64url(json_encode($header)) . '.' . b64url(json_encode($claims));

    $signature = '';
    $ok = openssl_sign($jwtUnsigned, $signature, $sa['private_key'], 'sha256');
    if (!$ok) {
        throw new Exception("No se pudo firmar JWT");
    }

    $jwt = $jwtUnsigned . '.' . b64url($signature);

    $ch = curl_init('https://oauth2.googleapis.com/token');
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => ['Content-Type: application/x-www-form-urlencoded'],
        CURLOPT_POSTFIELDS => http_build_query([
        'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion' => $jwt
        ]),
    ]);

    $resp = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    if ($resp === false) throw new Exception("OAuth error: $err");
    $json = json_decode($resp, true);

    if ($code < 200 || $code >= 300) {
        throw new Exception("OAuth HTTP $code: " . ($json['error_description'] ?? $resp));
    }

    if (empty($json['access_token'])) {
        throw new Exception("No access_token en respuesta OAuth");
    }

    return $json['access_token'];
}

function fcm_send_to_topic($projectId, $accessToken, $topic, $title, $body, array $data) {
    $url = "https://fcm.googleapis.com/v1/projects/{$projectId}/messages:send";

    $payload = [
        'message' => [
        'topic' => $topic,
        'notification' => [
            'title' => $title,
            'body'  => $body,
        ],
        'data' => array_map('strval', $data),
        'android' => [
            'priority' => 'HIGH',
            'notification' => [
            'channel_id' => 'tvc_citas_high',
            'sound' => 'default',
            ],
        ],
        'apns' => [
            'headers' => [
            'apns-priority' => '10',
            ],
            'payload' => [
            'aps' => [
                'sound' => 'default',
            ],
            ],
        ],
        ],
    ];

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
        "Authorization: Bearer {$accessToken}",
        "Content-Type: application/json; charset=utf-8",
        ],
        CURLOPT_POSTFIELDS => json_encode($payload),
    ]);

    $resp = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    $err  = curl_error($ch);
    curl_close($ch);

    if ($resp === false) {
        throw new Exception("FCM error: $err");
    }

    $json = json_decode($resp, true);
    if ($code < 200 || $code >= 300) {
        throw new Exception("FCM HTTP $code: $resp");
    }

    return $json;
}

// ======================= Cron logic =======================

try {
    $serviceAccountPath = __DIR__ . '/firebase-service-account.json';
    $projectId = getenv('FIREBASE_PROJECT_ID');
    if (!$projectId) throw new Exception("FIREBASE_PROJECT_ID no configurado en .env");

    $accessToken = get_access_token_from_sa($serviceAccountPath);

    $from = (new DateTime('+29 minutes'))->format('Y-m-d H:i:s');
    $to   = (new DateTime('+31 minutes'))->format('Y-m-d H:i:s');

    $stmt = $pdo->prepare("
        SELECT id, reportero_id, fecha_cita
        FROM noticias
        WHERE pendiente = 1
        AND hora_llegada IS NULL
        AND fecha_cita IS NOT NULL
        AND fecha_cita >= :from
        AND fecha_cita <  :to
        AND notificacion_cita_30m_enviada = 0
        LIMIT 200
    ");
    $stmt->execute([':from' => $from, ':to' => $to]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $sent = 0;
    foreach ($rows as $n) {
        $noticiaId = (int)$n['id'];
        $reporteroId = (int)($n['reportero_id'] ?? 0);

        $title = 'Cita próxima';
        $body  = 'Tu cita está próxima ¡Prepara tu equipo!';

        $data = [
        'tipo' => 'cita_proxima',
        'noticia_id' => (string)$noticiaId,
        ];

        fcm_send_to_topic($projectId, $accessToken, 'rol_admin', $title, $body, $data);

        // 2) Reportero asignado (topic)
        if ($reporteroId > 0) {
        fcm_send_to_topic($projectId, $accessToken, "reportero_{$reporteroId}", $title, $body, $data);
        }

        $up = $pdo->prepare("
        UPDATE noticias
        SET notificacion_cita_30m_enviada = 1,
            notificacion_cita_30m_at = NOW()
        WHERE id = ?
        LIMIT 1
        ");
        $up->execute([$noticiaId]);

        $sent++;
    }

    echo json_encode(['success' => true, 'checked' => count($rows), 'sent' => $sent]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}

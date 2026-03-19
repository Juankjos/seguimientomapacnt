<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

require __DIR__ . '/config.php';
require __DIR__ . '/fcm.php';

date_default_timezone_set('America/Mexico_City');

header('Content-Type: application/json; charset=utf-8');

try {
    $now  = new DateTimeImmutable('now', new DateTimeZone('America/Mexico_City'));
    $from = $now->modify('+29 minutes')->format('Y-m-d H:i:s');
    $to   = $now->modify('+31 minutes')->format('Y-m-d H:i:s');

    $stmt = $pdo->prepare("
        SELECT
            n.id,
            n.reportero_id,
            n.noticia,
            n.fecha_cita
        FROM noticias n
        WHERE n.pendiente = 1
            AND n.hora_llegada IS NULL
            AND n.fecha_cita IS NOT NULL
            AND n.reportero_id IS NOT NULL
            AND n.notificacion_cita_30m_enviada = 0
            AND n.fecha_cita >= :from
            AND n.fecha_cita < :to
        ORDER BY n.fecha_cita ASC
        LIMIT 200
    ");
    $stmt->execute([
        ':from' => $from,
        ':to'   => $to,
    ]);

    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    $checked = count($rows);
    $sent = 0;
    $errors = [];

    foreach ($rows as $n) {
        $noticiaId   = (int)$n['id'];
        $reporteroId = (int)($n['reportero_id'] ?? 0);
        $tituloNota  = trim((string)($n['noticia'] ?? 'Noticia'));
        $fechaCitaDb = trim((string)($n['fecha_cita'] ?? ''));

        if ($reporteroId <= 0 || $fechaCitaDb === '') {
            continue;
        }

        try {
            $dtCita = new DateTimeImmutable($fechaCitaDb, new DateTimeZone('America/Mexico_City'));
            $horaTxt = $dtCita->format('h:i A');

            $title = 'Cita próxima';
            $body  = "Tu cita \"{$tituloNota}\" es a las {$horaTxt}. Prepárate.";

            $data = [
                'tipo'       => 'cita_proxima',
                'noticia_id' => (string)$noticiaId,
            ];

            $result = fcm_send_topic([
                'topic' => "reportero_{$reporteroId}",
                'title' => $title,
                'body'  => $body,
                'data'  => $data,
            ]);

            $code = (int)($result['code'] ?? 0);
            if ($code < 200 || $code >= 300) {
                throw new Exception('FCM devolvió código ' . $code . ': ' . ($result['resp'] ?? 'sin respuesta'));
            }

            $up = $pdo->prepare("
                UPDATE noticias
                SET notificacion_cita_30m_enviada = 1,
                    notificacion_cita_30m_at = NOW()
                WHERE id = ?
                    AND notificacion_cita_30m_enviada = 0
                LIMIT 1
            ");
            $up->execute([$noticiaId]);

            if ($up->rowCount() > 0) {
                $sent++;
            }

        } catch (Throwable $e) {
            $errors[] = [
                'noticia_id' => $noticiaId,
                'error' => $e->getMessage(),
            ];
            error_log("cron_notificar_citas_30m.php noticia_id={$noticiaId}: " . $e->getMessage());
        }
    }

    echo json_encode([
        'success' => true,
        'window_from' => $from,
        'window_to'   => $to,
        'checked' => $checked,
        'sent' => $sent,
        'errors' => $errors,
    ], JSON_UNESCAPED_UNICODE);
    exit;

} catch (Throwable $e) {
    http_response_code(500);
    error_log("cron_notificar_citas_30m.php fatal: " . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage(),
    ], JSON_UNESCAPED_UNICODE);
    exit;
}
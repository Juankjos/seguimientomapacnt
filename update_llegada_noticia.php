<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');

require __DIR__ . '/config.php';
require __DIR__ . '/require_auth.php';
require __DIR__ . '/mailer.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

function fmt_dt_mx(?string $mysql): string {
    if ($mysql === null || trim($mysql) === '') return 'Sin cita programada';
    try {
        $dt = new DateTime($mysql, new DateTimeZone('America/Mexico_City'));
        return $dt->format('d/m/Y H:i') . ' (hora local)';
    } catch (Throwable $e) {
        return $mysql;
    }
}

// INPUT
$raw = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

// AUTH
$user = require_auth($pdo, is_array($in) ? $in : []);

$noticiaId = isset($in['noticia_id']) ? (int)$in['noticia_id'] : 0;
$latitud   = isset($in['latitud']) ? trim((string)$in['latitud']) : '';
$longitud  = isset($in['longitud']) ? trim((string)$in['longitud']) : '';
$horaLlegada = isset($in['hora_llegada']) ? trim((string)$in['hora_llegada']) : '';

if ($noticiaId <= 0 || $latitud === '' || $longitud === '') {
    echo json_encode([
        'success' => false,
        'message' => 'Parámetros inválidos (noticia_id, latitud, longitud)',
    ]);
    exit;
}

if ($horaLlegada === '' || !preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $horaLlegada)) {
    echo json_encode(['success' => false, 'message' => 'hora_llegada inválida']);
    exit;
}

$debugFcm  = (isset($_GET['debug_fcm']) && $_GET['debug_fcm'] === '1');
$debugMail = (isset($_GET['debug_mail']) && $_GET['debug_mail'] === '1');

try {
    // Lee estado previo para evitar doble correo
    $pre = $pdo->prepare("SELECT id, noticia, cliente_id, fecha_cita, hora_llegada, reportero_id FROM noticias WHERE id = :id LIMIT 1");
    $pre->execute([':id' => $noticiaId]);
    $prev = $pre->fetch(PDO::FETCH_ASSOC);

    if (!$prev) {
        echo json_encode(['success' => false, 'message' => 'No se encontró la noticia']);
        exit;
    }

    $yaTeniaLlegada = !empty($prev['hora_llegada']);
    $clienteId = !empty($prev['cliente_id']) ? (int)$prev['cliente_id'] : null;
    $tituloNoticia = (string)($prev['noticia'] ?? 'Noticia');
    $fechaCitaDb = $prev['fecha_cita'] ?? null;

    // UPDATE llegada
    $sql = "
        UPDATE noticias
        SET
            hora_llegada = STR_TO_DATE(:hora, '%Y-%m-%d %H:%i:%s'),
            llegada_latitud = :lat,
            llegada_longitud = :lon
        WHERE id = :id
        LIMIT 1
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([
        ':hora' => $horaLlegada,
        ':lat'  => $latitud,
        ':lon'  => $longitud,
        ':id'   => $noticiaId,
    ]);

    // FCM a admins (tu lógica original)
    $q = $pdo->prepare("
        SELECT n.noticia, r.nombre AS reportero_nombre
        FROM noticias n
        LEFT JOIN reporteros r ON r.id = n.reportero_id
        WHERE n.id = :id
        LIMIT 1
    ");
    $q->execute([':id' => $noticiaId]);
    $row = $q->fetch(PDO::FETCH_ASSOC) ?: [];

    $nombreRep = isset($row['reportero_nombre']) ? trim((string)$row['reportero_nombre']) : '';

    $fcmRes = null;
    $fcmErr = null;

    try {
        $fcmPath = __DIR__ . '/fcm.php';
        if (!file_exists($fcmPath)) {
            throw new Exception("No existe fcm.php en {$fcmPath}");
        }

        require_once $fcmPath;

        $body = $nombreRep !== ''
            ? "El reportero {$nombreRep} se encuentra en el destino."
            : "El reportero se encuentra en el destino.";

        $fcmRes = fcm_send_topic([
            'topic' => 'rol_admin',
            'title' => 'Reporte de trayecto',
            'body'  => $body . " ({$tituloNoticia})",
            'data'  => [
                'tipo' => 'llegada_destino',
                'noticia_id' => (string)$noticiaId,
            ],
        ]);

        error_log("FCM llegada_destino rol_admin result=" . json_encode($fcmRes));
    } catch (Throwable $e) {
        $fcmErr = $e->getMessage();
        error_log("FCM llegada_destino error: " . $fcmErr);
    }

    // MAIL al cliente (solo la primera vez)
    $mailStatus = 'skipped';
    $mailError  = null;
    $mailTo     = null;

    try {
        if ($yaTeniaLlegada) {
            $mailStatus = 'skipped_already_arrived';
        } elseif ($clienteId === null) {
            $mailStatus = 'skipped_no_cliente';
        } else {
            $stmtC = $pdo->prepare("SELECT nombre, correo FROM clientes WHERE id = ? LIMIT 1");
            $stmtC->execute([$clienteId]);
            $c = $stmtC->fetch(PDO::FETCH_ASSOC) ?: [];

            $nombreCliente = trim((string)($c['nombre'] ?? ''));
            $correoCliente = trim((string)($c['correo'] ?? ''));
            $mailTo = $correoCliente;

            if ($correoCliente === '') {
                $mailStatus = 'skipped_empty_email';
            } elseif (!filter_var($correoCliente, FILTER_VALIDATE_EMAIL)) {
                $mailStatus = 'skipped_invalid_email';
            } elseif (!is_array($mailCfg) || trim((string)($mailCfg['password'] ?? '')) === '') {
                $mailStatus = 'skipped_smtp_not_configured';
            } else {
                $citaTxt = fmt_dt_mx($fechaCitaDb);

                $subject = 'Llegada al destino';
                $body =
                    "Hola" . ($nombreCliente !== '' ? " {$nombreCliente}" : "") . ",\n\n" .
                    "¡El reportero ha llegado a tu cita!\n\n" .
                    "Asunto: {$tituloNoticia}\n" .
                    "Cita: {$citaTxt}\n" .
                    "Hora de llegada: {$horaLlegada}\n\n" .
                    "Soporte TVC Tepa";

                smtp_send_mail($mailCfg, $correoCliente, $nombreCliente, $subject, $body);
                $mailStatus = 'sent';
            }
        }
    } catch (Throwable $e) {
        $mailStatus = 'error';
        $mailError  = $e->getMessage();
        error_log("MAIL llegada error noticia_id={$noticiaId}: " . $mailError);
    }

    if ($debugFcm || $debugMail) {
        $out = [
            'success' => true,
            'message' => 'Llegada registrada (debug)',
            'hora_llegada' => $horaLlegada,
            'fcm' => $fcmRes,
            'fcm_error' => $fcmErr,
        ];
        if ($debugMail) {
            $out['mail_status'] = $mailStatus;
            $out['mail_to'] = $mailTo;
            $out['mail_error'] = $mailError;
        }
        echo json_encode($out);
        exit;
    }

    echo json_encode([
        'success' => true,
        'message' => 'Hora y coordenadas de llegada registradas correctamente',
        'hora_llegada' => $horaLlegada,
    ]);
    exit;

} catch (Throwable $e) {
    http_response_code(500);
    error_log("update_llegada_noticia.php error: " . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Error al actualizar llegada']);
    exit;
}

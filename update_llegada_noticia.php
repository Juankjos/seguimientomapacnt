<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');

require __DIR__ . '/config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$raw = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = is_array($json) ? $json : $_POST;

$noticiaId = isset($in['noticia_id']) ? (int)$in['noticia_id'] : 0;
$latitud   = isset($in['latitud']) ? trim((string)$in['latitud']) : '';
$longitud  = isset($in['longitud']) ? trim((string)$in['longitud']) : '';

if ($noticiaId <= 0 || $latitud === '' || $longitud === '') {
    echo json_encode([
        'success' => false,
        'message' => 'Parámetros inválidos (noticia_id, latitud, longitud)',
    ]);
    exit;
}

$debug = (isset($_GET['debug_fcm']) && $_GET['debug_fcm'] === '1');

try {
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
        ':lat' => $latitud,
        ':lon' => $longitud,
        ':id'  => $noticiaId,
    ]);

    $horaLlegada = isset($in['hora_llegada']) ? trim((string)$in['hora_llegada']) : '';
    if ($horaLlegada === '' || !preg_match('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/', $horaLlegada)) {
        echo json_encode(['success' => false, 'message' => 'hora_llegada inválida']);
        exit;
    }

    if ($stmt->rowCount() === 0) {
        echo json_encode(['success' => false, 'message' => 'No se encontró la noticia o no hubo cambios']);
        exit;
    }

    $q = $pdo->prepare("
        SELECT n.noticia, r.nombre AS reportero_nombre
        FROM noticias n
        LEFT JOIN reporteros r ON r.id = n.reportero_id
        WHERE n.id = :id
        LIMIT 1
    ");
    $q->execute([':id' => $noticiaId]);
    $row = $q->fetch(PDO::FETCH_ASSOC) ?: [];

    $tituloNoticia = isset($row['noticia']) ? (string)$row['noticia'] : 'Noticia';
    $nombreRep = isset($row['reportero_nombre']) ? trim((string)$row['reportero_nombre']) : '';

    // ----------- Notificación FCM a Admins -----------
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
        'body'  => $body . " ($tituloNoticia)",
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

    if ($debug) {
        echo json_encode([
        'success' => true,
        'message' => 'Llegada registrada + debug FCM',
        'hora_llegada' => date('Y-m-d H:i:s'),
        'fcm' => $fcmRes,
        'fcm_error' => $fcmErr,
        ]);
        exit;
    }

    echo json_encode([
        'success' => true,
        'message' => 'Hora y coordenadas de llegada registradas correctamente',
        'hora_llegada' => date('Y-m-d H:i:s'),
    ]);
    exit;

} catch (Throwable $e) {
    http_response_code(500);
    error_log("update_llegada_noticia.php error: " . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Error al actualizar llegada']);
    exit;
}

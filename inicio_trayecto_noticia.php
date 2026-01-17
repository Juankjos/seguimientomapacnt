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

// ✅ Acepta JSON o x-www-form-urlencoded
$raw = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = is_array($json) ? $json : $_POST;

$noticiaId = isset($in['noticia_id']) ? (int)$in['noticia_id'] : 0;
if ($noticiaId <= 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
    exit;
}

$debug = (isset($_GET['debug_fcm']) && $_GET['debug_fcm'] === '1');

try {
    $q = $pdo->prepare("
        SELECT n.noticia, r.nombre AS reportero_nombre
        FROM noticias n
        LEFT JOIN reporteros r ON r.id = n.reportero_id
        WHERE n.id = :id
        LIMIT 1
    ");
    $q->execute([':id' => $noticiaId]);
    $row = $q->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(['success' => false, 'message' => 'No existe la noticia']);
        exit;
    }

    $tituloNoticia = (string)$row['noticia'];
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
        ? "El reportero {$nombreRep} está en camino al destino."
        : "El reportero está en camino al destino.";

        $fcmRes = fcm_send_topic([
        'topic' => 'rol_admin',
        'title' => 'Reporte de trayecto',
        'body'  => $body . " ($tituloNoticia)",
        'data'  => [
            'tipo' => 'inicio_trayecto',
            'noticia_id' => (string)$noticiaId,
        ],
        ]);

        error_log("FCM inicio_trayecto rol_admin result=" . json_encode($fcmRes));
    } catch (Throwable $e) {
        $fcmErr = $e->getMessage();
        error_log("FCM inicio_trayecto error: " . $fcmErr);
    }

    if ($debug) {
        echo json_encode([
        'success' => true,
        'message' => 'Inicio trayecto + debug FCM',
        'fcm' => $fcmRes,
        'fcm_error' => $fcmErr,
        ]);
        exit;
    }

    echo json_encode(['success' => true, 'message' => 'Notificación enviada a admins']);
    exit;

} catch (Throwable $e) {
    http_response_code(500);
    error_log("inicio_trayecto_noticia.php error: " . $e->getMessage());
    echo json_encode(['success' => false, 'message' => 'Error interno']);
    exit;
}

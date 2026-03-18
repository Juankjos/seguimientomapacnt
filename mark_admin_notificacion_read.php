<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');

require __DIR__ . '/config.php';
require __DIR__ . '/require_auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in   = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

$user = require_auth($pdo, is_array($in) ? $in : []);
if (($user['role'] ?? '') !== 'admin') {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Solo admins']);
    exit;
}

$adminId = (int)($user['id'] ?? 0);
$notifId = isset($in['notificacion_id']) ? (int)$in['notificacion_id'] : 0;

if ($notifId <= 0) {
    echo json_encode(['success' => false, 'message' => 'notificacion_id inválido']);
    exit;
}

try {
    $q = $pdo->prepare("
        INSERT IGNORE INTO admin_notificaciones_leidas (
            notificacion_id,
            admin_id,
            read_at
        ) VALUES (
            :notificacion_id,
            :admin_id,
            NOW()
        )
    ");
    $q->execute([
        ':notificacion_id' => $notifId,
        ':admin_id' => $adminId,
    ]);

    echo json_encode(['success' => true]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error interno']);
}
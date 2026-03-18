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
$limit   = isset($in['limit']) ? (int)$in['limit'] : 20;
$limit   = max(1, min(50, $limit));

try {
    $qCount = $pdo->prepare("
        SELECT COUNT(*) AS total
        FROM admin_notificaciones n
        LEFT JOIN admin_notificaciones_leidas l
            ON l.notificacion_id = n.id
            AND l.admin_id = :admin_id
        WHERE l.notificacion_id IS NULL
    ");
    $qCount->execute([':admin_id' => $adminId]);
    $unread = (int)($qCount->fetchColumn() ?: 0);

    $q = $pdo->prepare("
        SELECT
            n.id,
            n.tipo,
            n.noticia_id,
            n.reportero_id,
            n.mensaje,
            n.created_at,
            CASE WHEN l.notificacion_id IS NULL THEN 0 ELSE 1 END AS leida
        FROM admin_notificaciones n
        LEFT JOIN admin_notificaciones_leidas l
            ON l.notificacion_id = n.id
            AND l.admin_id = :admin_id
        ORDER BY n.created_at DESC, n.id DESC
        LIMIT :lim
    ");
    $q->bindValue(':admin_id', $adminId, PDO::PARAM_INT);
    $q->bindValue(':lim', $limit, PDO::PARAM_INT);
    $q->execute();

    echo json_encode([
        'success' => true,
        'unread_count' => $unread,
        'data' => $q->fetchAll(PDO::FETCH_ASSOC),
    ]);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error interno',
    ]);
}
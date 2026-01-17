<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$idsRaw = $_POST['noticia_ids'] ?? '';
$targetRaw = $_POST['nuevo_reportero_id'] ?? '';

$ids = json_decode($idsRaw, true);
if (!is_array($ids) || count($ids) === 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_ids inválido']);
    exit;
}

$ids = array_values(array_filter(array_map('intval', $ids), fn($v) => $v > 0));
if (count($ids) === 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_ids vacío']);
    exit;
}

$nuevoReporteroId = null;
if ($targetRaw !== '' && intval($targetRaw) > 0) {
    $nuevoReporteroId = intval($targetRaw);

    // valida que exista y sea reportero
    $st = $pdo->prepare("SELECT id, role FROM reporteros WHERE id = ? LIMIT 1");
    $st->execute([$nuevoReporteroId]);
    $u = $st->fetch();
    if (!$u || $u['role'] !== 'reportero') {
        echo json_encode(['success' => false, 'message' => 'nuevo_reportero_id inválido']);
        exit;
    }
}

try {
    $placeholders = implode(',', array_fill(0, count($ids), '?'));

    if ($nuevoReporteroId === null) {
        $sql = "UPDATE noticias SET reportero_id = NULL WHERE id IN ($placeholders)";
        $stmt = $pdo->prepare($sql);
        $stmt->execute($ids);
    } else {
        $sql = "UPDATE noticias SET reportero_id = ? WHERE id IN ($placeholders)";
        $stmt = $pdo->prepare($sql);
        $stmt->execute(array_merge([$nuevoReporteroId], $ids));
    }

    echo json_encode([
        'success' => true,
        'message' => 'Noticias reasignadas',
        'updated' => $stmt->rowCount(),
    ]);
    exit;

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error al reasignar', 'error' => $e->getMessage()]);
    exit;
}

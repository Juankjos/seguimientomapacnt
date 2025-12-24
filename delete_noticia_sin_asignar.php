<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$noticiaId = isset($_POST['noticia_id']) ? intval($_POST['noticia_id']) : 0;
if ($noticiaId <= 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
    exit;
}

try {
    // 1) Validar que exista y que NO tenga reportero asignado
    $stmt0 = $pdo->prepare("SELECT reportero_id FROM noticias WHERE id = ? LIMIT 1");
    $stmt0->execute([$noticiaId]);
    $row = $stmt0->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(['success' => false, 'message' => 'Noticia no encontrada']);
        exit;
    }

    // Si tiene reportero asignado (no null), NO se permite borrar aquí
    if ($row['reportero_id'] !== null) {
        echo json_encode(['success' => false, 'message' => 'No se puede borrar: la noticia ya tiene reportero asignado']);
        exit;
    }

    // 2) Borrar
    $stmt = $pdo->prepare("DELETE FROM noticias WHERE id = ? LIMIT 1");
    $stmt->execute([$noticiaId]);

    echo json_encode(['success' => true, 'message' => 'Noticia borrada']);
    exit;

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error al borrar noticia', 'error' => $e->getMessage()]);
    exit;
}

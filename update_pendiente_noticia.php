<?php
require 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Método no permitido',
    ]);
    exit;
}

$noticiaId = isset($_POST['noticia_id']) ? intval($_POST['noticia_id']) : 0;

if ($noticiaId <= 0) {
    echo json_encode([
        'success' => false,
        'message' => 'Parámetro noticia_id inválido',
    ]);
    exit;
}

try {
    $sql = "
        UPDATE noticias
        SET pendiente = 0
        WHERE id = :id
        LIMIT 1
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([':id' => $noticiaId]);

    if ($stmt->rowCount() === 0) {
        echo json_encode([
            'success' => false,
            'message' => 'No se encontró la noticia o ya no estaba pendiente',
        ]);
        exit;
    }

    echo json_encode([
        'success' => true,
        'message' => 'Noticia eliminada de pendientes',
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar pendiente',
        'error'   => $e->getMessage(),
    ]);
}

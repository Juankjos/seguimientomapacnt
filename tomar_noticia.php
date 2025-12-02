<?php
require 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$reporteroId = isset($_POST['reportero_id']) ? intval($_POST['reportero_id']) : 0;
$noticiaId   = isset($_POST['noticia_id'])   ? intval($_POST['noticia_id'])   : 0;

if ($reporteroId <= 0 || $noticiaId <= 0) {
    echo json_encode(['success' => false, 'message' => 'Datos inválidos']);
    exit;
}

// Solo asignar si la noticia aún no tiene reportero (evitar que se la "roben")
$sql = "UPDATE noticias 
        SET reportero_id = :reportero_id 
        WHERE id = :id AND reportero_id IS NULL";

$stmt = $pdo->prepare($sql);
$stmt->execute([
    ':reportero_id' => $reporteroId,
    ':id'           => $noticiaId
]);

if ($stmt->rowCount() > 0) {
    echo json_encode([
        'success' => true,
        'message' => 'Noticia asignada correctamente'
    ]);
} else {
    echo json_encode([
        'success' => false,
        'message' => 'La noticia ya fue tomada por otro reportero o no existe'
    ]);
}

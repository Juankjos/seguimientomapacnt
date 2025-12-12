<?php
require 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Método no permitido'
    ]);
    exit;
}

$noticiaId = isset($_POST['noticia_id']) ? intval($_POST['noticia_id']) : 0;
$latitud   = isset($_POST['latitud']) ? trim($_POST['latitud']) : null;
$longitud  = isset($_POST['longitud']) ? trim($_POST['longitud']) : null;

if ($noticiaId <= 0 || $latitud === null || $longitud === null) {
    echo json_encode([
        'success' => false,
        'message' => 'Parámetros inválidos (noticia_id, latitud, longitud)'
    ]);
    exit;
}

try {
    $sql = "
        UPDATE noticias
        SET 
            hora_llegada = NOW(),
            llegada_latitud = :lat,
            llegada_longitud = :lon
        WHERE id = :id
        LIMIT 1
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([
        ':lat' => $latitud,
        ':lon' => $longitud,
        ':id'  => $noticiaId,
    ]);

    if ($stmt->rowCount() === 0) {
        echo json_encode([
            'success' => false,
            'message' => 'No se encontró la noticia o no hubo cambios'
        ]);
        exit;
    }

    echo json_encode([
        'success' => true,
        'message' => 'Hora y coordenadas de llegada registradas correctamente',
        'hora_llegada' => date('Y-m-d H:i:s'),
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar llegada',
        'error'   => $e->getMessage(),
    ]);
}

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
$latitud   = isset($_POST['latitud'])    ? trim($_POST['latitud'])      : null;
$longitud  = isset($_POST['longitud'])   ? trim($_POST['longitud'])     : null;
$domicilio = isset($_POST['domicilio'])  ? trim($_POST['domicilio'])    : null;

if ($noticiaId <= 0 || $latitud === null || $longitud === null) {
    echo json_encode([
        'success' => false,
        'message' => 'Datos inválidos'
    ]);
    exit;
}

try {
    $sql = "
        UPDATE noticias
        SET 
            latitud  = :latitud,
            longitud = :longitud
    ";

    if ($domicilio !== null && $domicilio !== '') {
        $sql .= ",
            domicilio = :domicilio
        ";
    }

    $sql .= ",
            ultima_mod = NOW()
        WHERE id = :id
        LIMIT 1
    ";

    $stmt = $pdo->prepare($sql);

    $params = [
        ':latitud'  => $latitud,
        ':longitud' => $longitud,
        ':id'       => $noticiaId,
    ];

    if ($domicilio !== null && $domicilio !== '') {
        $params[':domicilio'] = $domicilio;
    }

    $stmt->execute($params);

    if ($stmt->rowCount() > 0) {
        echo json_encode([
            'success' => true,
            'message' => 'Ubicación actualizada correctamente',
        ]);
    } else {
        echo json_encode([
            'success' => false,
            'message' => 'No se actualizó la ubicación (¿datos iguales o id inexistente?)',
        ]);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar ubicación',
        'error'   => $e->getMessage(),
    ]);
}

<?php
require 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$noticia     = isset($_POST['noticia'])     ? trim($_POST['noticia'])     : '';
$descripcion = isset($_POST['descripcion']) ? trim($_POST['descripcion']) : '';
$domicilio   = isset($_POST['domicilio'])   ? trim($_POST['domicilio'])   : '';
$reporteroId = isset($_POST['reportero_id']) && $_POST['reportero_id'] !== ''
    ? intval($_POST['reportero_id'])
    : null;
$fechaCita   = isset($_POST['fecha_cita'])  ? trim($_POST['fecha_cita'])  : '';

if ($noticia === '') {
    echo json_encode(['success' => false, 'message' => 'El campo noticia es obligatorio']);
    exit;
}

// Si viene vacío lo guardamos como NULL, si no como texto
$descripcionValue = $descripcion !== '' ? $descripcion : null;
$domicilioValue   = $domicilio   !== '' ? $domicilio   : null;
$fechaCitaValue   = $fechaCita   !== '' ? $fechaCita   : null;

try {
    $sql = "
        INSERT INTO noticias (
            noticia,
            descripcion,
            cliente_id,
            domicilio,
            reportero_id,
            fecha_cita,
            pendiente
        )
        VALUES (
            :noticia,
            :descripcion,
            NULL,
            :domicilio,
            :reportero_id,
            :fecha_cita,
            1
        )
    ";

    $stmt = $pdo->prepare($sql);

    // 👇 Dejamos que PDO infiera los tipos, sin PDO::PARAM_*
    $stmt->execute([
        ':noticia'      => $noticia,
        ':descripcion'  => $descripcionValue,
        ':domicilio'    => $domicilioValue,
        ':reportero_id' => $reporteroId,
        ':fecha_cita'   => $fechaCitaValue,
    ]);

    $newId = $pdo->lastInsertId();

    echo json_encode([
        'success' => true,
        'message' => 'Noticia creada correctamente',
        'id'      => $newId,
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al crear noticia',
        'error'   => $e->getMessage(),
    ]);
}

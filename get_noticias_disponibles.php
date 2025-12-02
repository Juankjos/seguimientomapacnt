<?php
require 'config.php';

// Noticias que no tienen reportero asignado (reportero_id IS NULL)
$sql = "
    SELECT
        n.id,
        n.noticia,
        n.descripcion,
        c.nombre AS cliente,
        n.domicilio,
        n.fecha_pago,
        n.fecha_cita,
        n.latitud,
        n.longitud
    FROM noticias n
    LEFT JOIN clientes c ON n.cliente_id = c.id
    WHERE n.reportero_id IS NULL
    ORDER BY n.id DESC
";

$stmt = $pdo->query($sql);
$rows = $stmt->fetchAll();

echo json_encode([
    'success' => true,
    'data'    => $rows
]);

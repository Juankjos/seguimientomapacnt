<?php
require 'config.php';

// Noticias que no tienen reportero asignado (reportero_id IS NULL)
$sql = "
    SELECT
        n.id,
        n.noticia,
        COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
        n.descripcion,
        c.nombre AS cliente,
        c.whatsapp AS cliente_whatsapp,
        n.domicilio,
        n.fecha_pago,
        n.fecha_cita,
        n.latitud,
        n.longitud,
        n.limite_tiempo_minutos,
    FROM noticias n
    LEFT JOIN clientes c ON n.cliente_id = c.id
    WHERE n.reportero_id IS NULL
        AND n.pendiente = 1
    ORDER BY n.id DESC
";

$stmt = $pdo->query($sql);
$rows = $stmt->fetchAll();

echo json_encode([
    'success' => true,
    'data'    => $rows
]);

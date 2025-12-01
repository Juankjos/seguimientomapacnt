<?php
require 'config.php';

$reporteroId = isset($_GET['reportero_id']) ? intval($_GET['reportero_id']) : 0;

if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
}

$sql = "
    SELECT
        n.id,
        n.noticia,
        c.nombre AS cliente,
        n.domicilio,
        r.nombre AS reportero,
        n.fecha_pago,
        n.fecha_cita,
        n.latitud,
        n.longitud
    FROM noticias n
    LEFT JOIN clientes c ON n.cliente_id = c.id
    INNER JOIN reporteros r ON n.reportero_id = r.id
    WHERE n.reportero_id = ?
    ORDER BY n.fecha_cita ASC, n.id ASC
";

$stmt = $pdo->prepare($sql);
$stmt->execute([$reporteroId]);
$rows = $stmt->fetchAll();

echo json_encode([
    'success' => true,
    'data'    => $rows
]);

<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

$clienteId = isset($_GET['cliente_id']) ? intval($_GET['cliente_id']) : 0;
if ($clienteId <= 0) {
    echo json_encode(['success' => false, 'message' => 'cliente_id inválido']);
    exit;
}

try {
    $sql = "
        SELECT
            n.id,
            n.noticia,
            COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
            n.descripcion,
            n.cliente_id,
            n.domicilio,
            n.ubicacion_en_mapa,
            n.reportero_id,
            r.nombre AS reportero,
            n.fecha_cita,
            n.pendiente,
            n.latitud,
            n.longitud,
            n.hora_llegada,
            n.tiempo_en_nota,
            n.ultima_mod,
            n.limite_tiempo_minutos
        FROM noticias n
        LEFT JOIN reporteros r ON n.reportero_id = r.id
        WHERE n.cliente_id = ?
        ORDER BY
        n.pendiente DESC,
        n.fecha_cita IS NULL,
        n.fecha_cita DESC,
        n.id DESC
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute([$clienteId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode(['success' => true, 'data' => $rows]);
    exit;

} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al obtener noticias del cliente',
        'error' => $e->getMessage(),
    ]);
    exit;
}
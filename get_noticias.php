<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');
// modo = 'admin' o 'reportero' (por defecto)
$modo = isset($_GET['modo']) ? $_GET['modo'] : 'reportero';

if ($modo === 'admin') {
    // 🔹 MODO ADMIN: ver TODAS las noticias (asignadas o no, pendientes o no)
    $sql = "
        SELECT
            n.id,
            n.noticia,
            COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
            n.descripcion,
            c.nombre AS cliente,
            n.cliente_id,
            c.whatsapp AS cliente_whatsapp,
            n.domicilio,
            n.ubicacion_en_mapa,
            n.reportero_id,
            r.nombre AS reportero,
            n.fecha_pago,
            n.fecha_cita,
            n.fecha_cita_anterior,
            n.fecha_cita_cambios,
            n.latitud,
            n.longitud,
            n.hora_llegada,
            n.llegada_latitud,
            n.llegada_longitud,
            n.pendiente,
            n.ruta_iniciada,
            n.ruta_iniciada_at,
            n.ultima_mod,
            n.tiempo_en_nota,
            n.limite_tiempo_minutos 
        FROM noticias n
        LEFT JOIN clientes c   ON n.cliente_id  = c.id
        LEFT JOIN reporteros r ON n.reportero_id = r.id
        ORDER BY 
            n.fecha_cita IS NULL, 
            n.fecha_cita ASC,
            n.id ASC
    ";

    try {
        $stmt = $pdo->query($sql);
        $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            'success' => true,
            'data'    => $rows,
        ]);
    } catch (Exception $e) {
        http_response_code(500);
        echo json_encode([
            'success' => false,
            'message' => 'Error al obtener noticias (admin)',
            'error'   => $e->getMessage(),
        ]);
    }
    exit;
}

// 🔹 MODO REPORTERO
$reporteroId = isset($_GET['reportero_id']) ? intval($_GET['reportero_id']) : 0;
$incluyeCerradas = isset($_GET['incluye_cerradas']) && $_GET['incluye_cerradas'] == '1';

if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
}
$sql = "
    SELECT
        n.id,
        n.noticia,
        COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
        n.descripcion,
        c.nombre AS cliente,
        n.cliente_id,
        c.whatsapp AS cliente_whatsapp,
        n.domicilio,
        n.ubicacion_en_mapa,
        n.reportero_id,
        r.nombre AS reportero,
        n.fecha_pago,
        n.fecha_cita,
        n.fecha_cita_anterior,
        n.fecha_cita_cambios,
        n.latitud,
        n.longitud,
        n.hora_llegada,
        n.llegada_latitud,
        n.llegada_longitud,
        n.pendiente,
        n.ruta_iniciada,
        n.ruta_iniciada_at,
        n.ultima_mod,
        n.tiempo_en_nota,
        n.limite_tiempo_minutos
    FROM noticias n
    LEFT JOIN clientes c ON n.cliente_id = c.id
    INNER JOIN reporteros r ON n.reportero_id = r.id
    WHERE n.reportero_id = ?
";

if (!$incluyeCerradas) {
    $sql .= " AND n.pendiente = 1 ";
}

$sql .= "
    ORDER BY
        n.pendiente DESC,
        n.fecha_cita IS NULL,
        n.fecha_cita ASC,
        n.id ASC
";

try {
    $stmt = $pdo->prepare($sql);
    $stmt->execute([$reporteroId]);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true,
        'data'    => $rows,
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al obtener noticias (reportero)',
        'error'   => $e->getMessage(),
    ]);
}

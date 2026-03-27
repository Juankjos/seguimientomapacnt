<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

$modo = isset($_GET['modo']) ? $_GET['modo'] : 'reportero';
$noticiaId = isset($_GET['noticia_id']) ? intval($_GET['noticia_id']) : 0;

if ($noticiaId <= 0) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'noticia_id inválido',
    ]);
    exit;
}

try {
    if ($modo === 'admin') {
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
                COALESCE(NULLIF(TRIM(r.nombre_pdf), ''), r.nombre) AS reportero,
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
            LEFT JOIN clientes c   ON n.cliente_id = c.id
            LEFT JOIN reporteros r ON n.reportero_id = r.id
            WHERE n.id = ?
            LIMIT 1
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([$noticiaId]);
    } else {
        $reporteroId = isset($_GET['reportero_id']) ? intval($_GET['reportero_id']) : 0;

        if ($reporteroId <= 0) {
            http_response_code(400);
            echo json_encode([
                'success' => false,
                'message' => 'reportero_id inválido',
            ]);
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
                COALESCE(NULLIF(TRIM(r.nombre_pdf), ''), r.nombre) AS reportero,
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
            WHERE n.id = ? AND n.reportero_id = ?
            LIMIT 1
        ";

        $stmt = $pdo->prepare($sql);
        $stmt->execute([$noticiaId, $reporteroId]);
    }

    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'message' => 'Noticia no encontrada',
        ]);
        exit;
    }

    echo json_encode([
        'success' => true,
        'data' => $row,
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al obtener detalle de noticia',
        'error' => $e->getMessage(),
    ]);
}
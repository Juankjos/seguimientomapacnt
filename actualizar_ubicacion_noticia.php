<?php
require 'config.php';
header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Método no permitido'
    ]);
    exit;
}

function normalize_mysql_datetime($v) {
    if ($v === null) return null;
    $s = trim((string)$v);
    if ($s === '') return null;

    $s = str_replace('T', ' ', $s);
    $s = substr($s, 0, 19);

    $dt = DateTime::createFromFormat('Y-m-d H:i:s', $s);
    if (!$dt) return null;

    return $dt->format('Y-m-d H:i:s');
}

$noticiaId = isset($_POST['noticia_id']) ? intval($_POST['noticia_id']) : 0;
$latitud   = isset($_POST['latitud'])    ? trim((string)$_POST['latitud'])  : null;
$longitud  = isset($_POST['longitud'])   ? trim((string)$_POST['longitud']) : null;

$ubicacionEnMapa = isset($_POST['ubicacion_en_mapa'])
    ? trim((string)$_POST['ubicacion_en_mapa'])
    : null;

if (($ubicacionEnMapa === null || $ubicacionEnMapa === '') && isset($_POST['domicilio'])) {
    $fallback = trim((string)$_POST['domicilio']);
    if ($fallback !== '') $ubicacionEnMapa = $fallback;
}

$ultimaMod = normalize_mysql_datetime($_POST['ultima_mod'] ?? null);
if ($ultimaMod === null) {
    $ultimaMod = date('Y-m-d H:i:s');
}

if ($noticiaId <= 0 || $latitud === null || $latitud === '' || $longitud === null || $longitud === '') {
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

    if ($ubicacionEnMapa !== null && $ubicacionEnMapa !== '') {
        $sql .= ",
            ubicacion_en_mapa = :ubicacion_en_mapa
        ";
    }

    $sql .= ",
            ultima_mod = :ultima_mod
        WHERE id = :id
        LIMIT 1
    ";

    $stmt = $pdo->prepare($sql);

    $params = [
        ':latitud'    => $latitud,
        ':longitud'   => $longitud,
        ':ultima_mod' => $ultimaMod,
        ':id'         => $noticiaId,
    ];

    if ($ubicacionEnMapa !== null && $ubicacionEnMapa !== '') {
        $params[':ubicacion_en_mapa'] = $ubicacionEnMapa;
    }

    $stmt->execute($params);

    echo json_encode([
        'success' => true,
        'message' => 'Ubicación actualizada correctamente',
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar ubicación',
        'error'   => $e->getMessage(),
    ]);
}

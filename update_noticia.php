<?php
require 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
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

$noticiaId   = isset($_POST['noticia_id']) ? intval($_POST['noticia_id']) : 0;
$role        = isset($_POST['role']) ? trim($_POST['role']) : 'reportero';

$titulo      = isset($_POST['noticia']) ? trim($_POST['noticia']) : null;
$descripcion = isset($_POST['descripcion']) ? trim($_POST['descripcion']) : null;
$fechaCita   = isset($_POST['fecha_cita']) ? trim($_POST['fecha_cita']) : null;

$ultimaMod = normalize_mysql_datetime($_POST['ultima_mod'] ?? null);
if ($ultimaMod === null) {
    $ultimaMod = date('Y-m-d H:i:s');
}

if ($noticiaId <= 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
    exit;
}

try {
    $stmt = $pdo->prepare("
        SELECT noticia, descripcion, fecha_cita, fecha_cita_anterior, fecha_cita_cambios
        FROM noticias
        WHERE id = ?
        LIMIT 1
    ");
    $stmt->execute([$noticiaId]);
    $actual = $stmt->fetch();

    if (!$actual) {
        echo json_encode(['success' => false, 'message' => 'Noticia no encontrada']);
        exit;
    }

    $updates = [];
    $params = [':id' => $noticiaId];

    $oldDesc  = $actual['descripcion'];
    $oldFecha = $actual['fecha_cita'];
    $cambios  = intval($actual['fecha_cita_cambios'] ?? 0);

    $fechaNueva = ($fechaCita !== null && $fechaCita !== '') ? $fechaCita : null;

    if ($role === 'admin') {
        if ($titulo !== null && $titulo !== '') {
            $updates[] = "noticia = :noticia";
            $params[':noticia'] = $titulo;
        }

        if ($descripcion !== null) {
            $updates[] = "descripcion = :descripcion";
            $params[':descripcion'] = ($descripcion === '') ? null : $descripcion;
        }

        if ($fechaCita !== null) {
            if (($oldFecha ?? '') !== ($fechaNueva ?? '')) {
                $updates[] = "fecha_cita_anterior = :fecha_anterior";
                $params[':fecha_anterior'] = $oldFecha;
            }

            $updates[] = "fecha_cita = :fecha_cita";
            $params[':fecha_cita'] = $fechaNueva;
        }
    } else {
        if ($titulo !== null && $titulo !== '') {
            echo json_encode(['success' => false, 'message' => 'No tienes permiso para cambiar el título']);
            exit;
        }

        if ($descripcion !== null) {
            $descVacia = ($oldDesc === null || trim((string)$oldDesc) === '');
            if (!$descVacia) {
                echo json_encode(['success' => false, 'message' => 'La descripción ya fue capturada y no se puede modificar']);
                exit;
            }

            if (trim($descripcion) === '') {
                echo json_encode(['success' => false, 'message' => 'La descripción no puede quedar vacía']);
                exit;
            }

            $updates[] = "descripcion = :descripcion";
            $params[':descripcion'] = $descripcion;
        }

        if ($fechaCita !== null) {
            $oldFechaStr = ($oldFecha ?? '');
            $newFechaStr = ($fechaNueva ?? '');

            $cambia = ($oldFechaStr !== $newFechaStr);

            if ($cambia) {
                if ($cambios >= 2) {
                    echo json_encode(['success' => false, 'message' => 'Límite alcanzado: ya no puedes cambiar la fecha de cita']);
                    exit;
                }

                if ($oldFecha !== null && $oldFecha !== '') {
                    $updates[] = "fecha_cita_anterior = :fecha_anterior";
                    $params[':fecha_anterior'] = $oldFecha;
                }

                $updates[] = "fecha_cita_cambios = fecha_cita_cambios + 1";
            }

            $updates[] = "fecha_cita = :fecha_cita";
            $params[':fecha_cita'] = $fechaNueva;
        }
    }

    if (empty($updates)) {
        echo json_encode(['success' => false, 'message' => 'No hay cambios para guardar']);
        exit;
    }

    $updates[] = "ultima_mod = :ultima_mod";
    $params[':ultima_mod'] = $ultimaMod;

    $sql = "UPDATE noticias SET " . implode(", ", $updates) . " WHERE id = :id LIMIT 1";
    $stmtUp = $pdo->prepare($sql);
    $stmtUp->execute($params);

    $stmt2 = $pdo->prepare("
        SELECT
        n.id, n.noticia, n.descripcion, n.domicilio, n.reportero_id,
        n.fecha_pago, n.fecha_cita, n.fecha_cita_anterior, n.fecha_cita_cambios,
        n.latitud, n.longitud, n.hora_llegada, n.llegada_latitud, n.llegada_longitud,
        n.pendiente, n.ultima_mod,
        r.nombre AS reportero
        FROM noticias n
        LEFT JOIN reporteros r ON n.reportero_id = r.id
        WHERE n.id = ?
        LIMIT 1
    ");
    $stmt2->execute([$noticiaId]);
    $row = $stmt2->fetch();

    echo json_encode(['success' => true, 'data' => $row]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error al actualizar', 'error' => $e->getMessage()]);
}

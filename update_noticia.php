<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

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

    if (strlen($s) >= 19) {
        $s = substr($s, 0, 19);
    }

    $dt = DateTime::createFromFormat('Y-m-d H:i:s', $s);
    if (!$dt) return null;

    return $dt->format('Y-m-d H:i:s');
}

$noticiaId = isset($_POST['noticia_id']) ? intval($_POST['noticia_id']) : 0;
$role      = isset($_POST['role']) ? trim($_POST['role']) : 'reportero';

$titulo      = array_key_exists('noticia', $_POST) ? trim((string)$_POST['noticia']) : null;
$descripcion = array_key_exists('descripcion', $_POST) ? trim((string)$_POST['descripcion']) : null;

$tipoDeNota = array_key_exists('tipo_de_nota', $_POST)
    ? trim((string)$_POST['tipo_de_nota'])
    : null;

if ($tipoDeNota !== null) {
    if ($tipoDeNota === '') {
        $tipoDeNota = null;
    } else {
        $allowed = ['Nota', 'Entrevista'];
        if (!in_array($tipoDeNota, $allowed, true)) {
            echo json_encode(['success' => false, 'message' => 'tipo_de_nota inválido']);
            exit;
        }
    }
}

$hasFechaCita = array_key_exists('fecha_cita', $_POST);
$fechaNueva = $hasFechaCita ? normalize_mysql_datetime($_POST['fecha_cita']) : null;

$ultimaMod = normalize_mysql_datetime($_POST['ultima_mod'] ?? null);
if ($ultimaMod === null) {
    $ultimaMod = date('Y-m-d H:i:s');
}

$hasRutaIniciada = array_key_exists('ruta_iniciada', $_POST);
$rutaIniciadaReq = $hasRutaIniciada ? intval($_POST['ruta_iniciada']) : null;

$hasTiempoNota = array_key_exists('tiempo_en_nota', $_POST);
$tiempoNotaReq = $hasTiempoNota ? intval((string)$_POST['tiempo_en_nota']) : null;

$hasLimiteTiempo = array_key_exists('limite_tiempo_minutos', $_POST);
$limiteTiempoReq = $hasLimiteTiempo ? intval((string)$_POST['limite_tiempo_minutos']) : null;

if ($hasLimiteTiempo) {
    if ($limiteTiempoReq === null || $limiteTiempoReq < 60) {
        echo json_encode(['success' => false, 'message' => 'limite_tiempo_minutos debe ser mínimo 60']);
        exit;
    }
    if ($limiteTiempoReq > 65535) {
        echo json_encode(['success' => false, 'message' => 'limite_tiempo_minutos excede el máximo permitido']);
        exit;
    }
}

if ($noticiaId <= 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
    exit;
}

try {
    $stmt = $pdo->prepare("
        SELECT
            noticia,
            tipo_de_nota,
            descripcion,
            fecha_cita,
            fecha_cita_anterior,
            fecha_cita_cambios,
            ruta_iniciada,
            ruta_iniciada_at,
            hora_llegada,
            tiempo_en_nota,
            limite_tiempo_minutos
        FROM noticias
        WHERE id = ?
        LIMIT 1
    ");
    $stmt->execute([$noticiaId]);
    $actual = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$actual) {
        echo json_encode(['success' => false, 'message' => 'Noticia no encontrada']);
        exit;
    }

    $updates = [];
    $params  = [':id' => $noticiaId];

    $oldDesc  = $actual['descripcion'];
    $oldFecha = $actual['fecha_cita'];
    $cambios  = (int)($actual['fecha_cita_cambios'] ?? 0);
    $rutaIniciadaActual = (int)($actual['ruta_iniciada'] ?? 0);
    $oldTipo = $actual['tipo_de_nota'] ?? 'Nota';
    $oldLimite = (int)($actual['limite_tiempo_minutos'] ?? 60);

    $oldFechaStr = ($oldFecha ?? '');
    $newFechaStr = ($fechaNueva ?? '');
    $cambiaFecha = $hasFechaCita && ($oldFechaStr !== $newFechaStr);

    $horaLlegadaActual = $actual['hora_llegada'];
    $tiempoNotaActual  = $actual['tiempo_en_nota'];

    // ========================= ADMIN =========================
    if ($role === 'admin') {
        if ($titulo !== null && $titulo !== '') {
            $updates[] = "noticia = :noticia";
            $params[':noticia'] = $titulo;
        }

        if ($descripcion !== null) {
            $updates[] = "descripcion = :descripcion";
            $params[':descripcion'] = ($descripcion === '') ? null : $descripcion;
        }

        if ($tipoDeNota !== null && $tipoDeNota !== $oldTipo) {
            $updates[] = "tipo_de_nota = :tipo_de_nota";
            $params[':tipo_de_nota'] = $tipoDeNota;
        }

        if ($hasFechaCita) {
            if ($cambiaFecha) {
                $updates[] = "fecha_cita_anterior = :fecha_anterior";
                $params[':fecha_anterior'] = $oldFecha;

                $updates[] = "notificacion_cita_30m_enviada = 0";
                $updates[] = "notificacion_cita_30m_at = NULL";
            }

            $updates[] = "fecha_cita = :fecha_cita";
            $params[':fecha_cita'] = $fechaNueva;
        }
    }

    // ========================= REPORTERO =========================
    else {
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

        // Reportero SÍ puede cambiar tipo_de_nota
        if ($tipoDeNota !== null && $tipoDeNota !== $oldTipo) {
            $updates[] = "tipo_de_nota = :tipo_de_nota";
            $params[':tipo_de_nota'] = $tipoDeNota;
        }

        if ($hasFechaCita) {
            if ($cambiaFecha) {
                if ($cambios >= 2) {
                    echo json_encode(['success' => false, 'message' => 'Límite alcanzado: ya no puedes cambiar la fecha de cita']);
                    exit;
                }

                if ($oldFecha !== null && $oldFecha !== '') {
                    $updates[] = "fecha_cita_anterior = :fecha_anterior";
                    $params[':fecha_anterior'] = $oldFecha;
                }

                $updates[] = "fecha_cita_cambios = COALESCE(fecha_cita_cambios, 0) + 1";

                $updates[] = "notificacion_cita_30m_enviada = 0";
                $updates[] = "notificacion_cita_30m_at = NULL";
            }

            $updates[] = "fecha_cita = :fecha_cita";
            $params[':fecha_cita'] = $fechaNueva;
        }
    }

    // ========================= LIMITE TIEMPO =========================
    if ($hasLimiteTiempo) {
        if ($limiteTiempoReq !== $oldLimite) {
            $updates[] = "limite_tiempo_minutos = :limite_tiempo_minutos";
            $params[':limite_tiempo_minutos'] = $limiteTiempoReq;
        }
    }

    // ========================= RUTA INICIADA =========================
    if ($hasRutaIniciada && $rutaIniciadaReq === 1 && $rutaIniciadaActual === 0) {
        $updates[] = "ruta_iniciada = 1";
        $updates[] = "ruta_iniciada_at = COALESCE(ruta_iniciada_at, NOW())";
    }

    // ========================= TIEMPO EN NOTA =========================
    if ($hasTiempoNota) {
        if ($horaLlegadaActual === null || trim((string)$horaLlegadaActual) === '') {
            echo json_encode(['success' => false, 'message' => 'Aún no se ha finalizado la ruta para cronometrar nota']);
            exit;
        }
        if ($tiempoNotaReq === null || $tiempoNotaReq <= 0) {
            echo json_encode(['success' => false, 'message' => 'tiempo_en_nota inválido']);
            exit;
        }
        if ($tiempoNotaActual !== null && trim((string)$tiempoNotaActual) !== '') {
            if (intval($tiempoNotaActual) !== intval($tiempoNotaReq)) {
                echo json_encode(['success' => false, 'message' => 'El tiempo en nota ya fue registrado']);
                exit;
            }
        } else {
            $updates[] = "tiempo_en_nota = :tiempo_en_nota";
            $params[':tiempo_en_nota'] = $tiempoNotaReq;
        }
    }

    $wantsRutaIniciada = ($hasRutaIniciada && $rutaIniciadaReq === 1);
    $wantsTiempoNota   = $hasTiempoNota;

    if (empty($updates)) {
        if ($wantsRutaIniciada && $rutaIniciadaActual === 1) {
            $stmt2 = $pdo->prepare("
                SELECT
                    n.id,
                    n.noticia,
                    COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
                    n.descripcion,
                    n.domicilio,
                    n.ubicacion_en_mapa,
                    n.reportero_id,
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
                    n.ultima_mod,
                    n.ruta_iniciada,
                    n.ruta_iniciada_at,
                    n.tiempo_en_nota,
                    n.limite_tiempo_minutos,
                    r.nombre AS reportero
                FROM noticias n
                LEFT JOIN reporteros r ON n.reportero_id = r.id
                WHERE n.id = ?
                LIMIT 1
            ");
            $stmt2->execute([$noticiaId]);
            $row = $stmt2->fetch(PDO::FETCH_ASSOC);

            echo json_encode([
                'success' => true,
                'message' => 'Ruta ya estaba iniciada',
                'data' => $row
            ]);
            exit;
        }

        if ($wantsTiempoNota && $tiempoNotaActual !== null && trim((string)$tiempoNotaActual) !== ''
            && intval($tiempoNotaActual) === intval($tiempoNotaReq)) {

            $stmt2 = $pdo->prepare("
                SELECT
                    n.id,
                    n.noticia,
                    COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
                    n.descripcion,
                    n.domicilio,
                    n.ubicacion_en_mapa,
                    n.reportero_id,
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
                    n.ultima_mod,
                    n.ruta_iniciada,
                    n.ruta_iniciada_at,
                    n.tiempo_en_nota,
                    n.limite_tiempo_minutos,
                    r.nombre AS reportero
                FROM noticias n
                LEFT JOIN reporteros r ON n.reportero_id = r.id
                WHERE n.id = ?
                LIMIT 1
            ");
            $stmt2->execute([$noticiaId]);
            $row = $stmt2->fetch(PDO::FETCH_ASSOC);

            echo json_encode([
                'success' => true,
                'message' => 'Tiempo en nota ya estaba registrado',
                'data' => $row
            ]);
            exit;
        }

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
            n.id,
            n.noticia,
            COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
            n.descripcion,
            n.domicilio,
            n.ubicacion_en_mapa,
            n.reportero_id,
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
            n.ultima_mod,
            n.ruta_iniciada,
            n.ruta_iniciada_at,
            n.tiempo_en_nota,
            r.nombre AS reportero
        FROM noticias n
        LEFT JOIN reporteros r ON n.reportero_id = r.id
        WHERE n.id = ?
        LIMIT 1
    ");
    $stmt2->execute([$noticiaId]);
    $row = $stmt2->fetch(PDO::FETCH_ASSOC);

    echo json_encode(['success' => true, 'data' => $row]);
    exit;
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error al actualizar',
        'error' => $e->getMessage()
    ]);
    exit;
}

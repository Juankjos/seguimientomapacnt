<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

require __DIR__ . '/config.php';
require __DIR__ . '/require_auth.php';
require __DIR__ . '/mailer.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Método no permitido']);
  exit;
}

function normalize_mysql_datetime($v): ?string {
  if ($v === null) return null;
  $s = trim((string)$v);
  if ($s === '') return null;

  $s = str_replace('T', ' ', $s);
  if (strlen($s) >= 19) $s = substr($s, 0, 19);

  $dt = DateTime::createFromFormat('Y-m-d H:i:s', $s) ?: DateTime::createFromFormat('Y-m-d H:i', $s);
  if (!$dt) return null;

  return $dt->format('Y-m-d H:i:s');
}

function fmt_dt_mx_long(?string $mysql): string {
  if ($mysql === null || trim($mysql) === '') return 'Sin cita programada';

  try {
    $dt = new DateTime($mysql, new DateTimeZone('America/Mexico_City'));

    if (class_exists('IntlDateFormatter')) {
      $fmt = new IntlDateFormatter(
        'es_MX',
        IntlDateFormatter::FULL,
        IntlDateFormatter::SHORT,
        'America/Mexico_City',
        IntlDateFormatter::GREGORIAN,
        "EEEE d 'de' MMMM 'de' yyyy 'a las' h:mm a"
      );
      $out = $fmt->format($dt);
      return $out ? (string)$out : $dt->format('d/m/Y H:i');
    }

    return $dt->format('d/m/Y H:i') . ' (hora local)';
  } catch (Throwable $e) {
    return $mysql;
  }
}

function dt_date_part(?string $mysql): ?string {
  if ($mysql === null || trim($mysql) === '') return null;
  $dt = normalize_mysql_datetime($mysql);
  if ($dt === null) return null;
  return substr($dt, 0, 10); // YYYY-MM-DD
}

function dt_time_part(?string $mysql): ?string {
  if ($mysql === null || trim($mysql) === '') return null;
  $dt = normalize_mysql_datetime($mysql);
  if ($dt === null) return null;
  return substr($dt, 11, 5); // HH:MM
}

function normalize_text_nullable($v): ?string {
  if ($v === null) return null;
  $s = trim((string)$v);
  return $s === '' ? null : $s;
}

function join_campos_es(array $campos): string {
  $campos = array_values(array_unique(array_filter($campos)));
  $n = count($campos);

  if ($n === 0) return '';
  if ($n === 1) return $campos[0];
  if ($n === 2) return $campos[0] . ' y ' . $campos[1];

  $last = array_pop($campos);
  return implode(', ', $campos) . ' y ' . $last;
}

// -------------------- INPUT (JSON o FORM) --------------------
$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;
if (is_array($in)) $_POST = $in;

// -------------------- AUTH --------------------
$user = require_auth($pdo, is_array($in) ? $in : []);
$role = (string)($user['role'] ?? 'reportero');
$userId = (int)($user['id'] ?? 0);

if (!in_array($role, ['admin', 'reportero'], true)) {
  http_response_code(403);
  echo json_encode(['success' => false, 'message' => 'Rol inválido']);
  exit;
}

$debugMail = (isset($_GET['debug_mail']) && $_GET['debug_mail'] === '1');

// -------------------- INPUTS --------------------
$noticiaId = isset($_POST['noticia_id']) ? (int)$_POST['noticia_id'] : 0;
if ($noticiaId <= 0) {
  echo json_encode(['success' => false, 'message' => 'noticia_id inválido']);
  exit;
}

$titulo      = array_key_exists('noticia', $_POST) ? trim((string)$_POST['noticia']) : null;
$descripcion = array_key_exists('descripcion', $_POST) ? trim((string)$_POST['descripcion']) : null;

$tipoDeNota = array_key_exists('tipo_de_nota', $_POST) ? trim((string)$_POST['tipo_de_nota']) : null;
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

$hasClienteId = array_key_exists('cliente_id', $_POST);
$clienteIdReq = $hasClienteId ? trim((string)$_POST['cliente_id']) : null;

$clienteIdParsed = null;
if ($hasClienteId) {
  if ($clienteIdReq === '' || $clienteIdReq === '0') {
    $clienteIdParsed = null;
  } else {
    $tmp = (int)$clienteIdReq;
    $clienteIdParsed = ($tmp > 0) ? $tmp : null;
  }
}

$hasDomicilio = array_key_exists('domicilio', $_POST);
$domicilioReq = $hasDomicilio ? trim((string)$_POST['domicilio']) : null;
$domicilioParsed = $hasDomicilio ? (($domicilioReq === '') ? null : $domicilioReq) : null;

if (($hasClienteId || $hasDomicilio) && $role !== 'admin') {
  echo json_encode(['success' => false, 'message' => 'No tienes permiso para cambiar cliente/domicilio']);
  exit;
}

$hasFechaCita = array_key_exists('fecha_cita', $_POST);
$fechaNueva   = $hasFechaCita ? normalize_mysql_datetime($_POST['fecha_cita']) : null;

$ultimaMod = normalize_mysql_datetime($_POST['ultima_mod'] ?? null);
if ($ultimaMod === null) {
  $ultimaMod = (new DateTime('now', new DateTimeZone('America/Mexico_City')))
    ->format('Y-m-d H:i:s');
}

$hasRutaIniciada = array_key_exists('ruta_iniciada', $_POST);
$rutaIniciadaReq = $hasRutaIniciada ? (int)$_POST['ruta_iniciada'] : null;

$hasTiempoNota = array_key_exists('tiempo_en_nota', $_POST);
$tiempoNotaReq = $hasTiempoNota ? (int)$_POST['tiempo_en_nota'] : null;

$hasLimiteTiempo = array_key_exists('limite_tiempo_minutos', $_POST);
$limiteTiempoReq = $hasLimiteTiempo ? (int)$_POST['limite_tiempo_minutos'] : null;

if ($hasLimiteTiempo) {
  if ($limiteTiempoReq < 60) {
    echo json_encode(['success' => false, 'message' => 'limite_tiempo_minutos debe ser mínimo 60']);
    exit;
  }
  if ($limiteTiempoReq > 65535) {
    echo json_encode(['success' => false, 'message' => 'limite_tiempo_minutos excede el máximo permitido']);
    exit;
  }

  // 🔒 Seguridad: solo admin puede cambiar el límite
  if ($role !== 'admin') {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'No tienes permiso para cambiar limite_tiempo_minutos']);
    exit;
  }
}

try {
  $pdo->beginTransaction();

  // Lock noticia
  $stmt = $pdo->prepare("
    SELECT
      n.id,
      n.noticia,
      COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
      n.descripcion,
      n.cliente_id,
      c.nombre   AS cliente,
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
      n.ultima_mod,
      n.ruta_iniciada,
      n.ruta_iniciada_at,
      n.tiempo_en_nota,
      n.limite_tiempo_minutos
    FROM noticias n
    LEFT JOIN reporteros r ON n.reportero_id = r.id
    LEFT JOIN clientes  c ON n.cliente_id  = c.id
    WHERE n.id = ?
    LIMIT 1
    FOR UPDATE
  ");
  $stmt->execute([$noticiaId]);
  $actual = $stmt->fetch(PDO::FETCH_ASSOC);

  if (!$actual) {
    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'Noticia no encontrada']);
    exit;
  }

  // Seguridad: reportero solo su propia noticia
  $repIdNoticia = (int)($actual['reportero_id'] ?? 0);
  if ($role === 'reportero' && $repIdNoticia > 0 && $repIdNoticia !== $userId) {
    $pdo->rollBack();
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'No puedes modificar una noticia que no te pertenece']);
    exit;
  }

  // Old values
  $oldDesc  = $actual['descripcion'];
  $oldFecha = (string)($actual['fecha_cita'] ?? '');
  $cambios  = (int)($actual['fecha_cita_cambios'] ?? 0);

  $rutaIniciadaActual = (int)($actual['ruta_iniciada'] ?? 0);
  $oldTipo   = (string)($actual['tipo_de_nota'] ?? 'Nota');
  $oldLimite = (int)($actual['limite_tiempo_minutos'] ?? 60);

  $oldClienteId = !empty($actual['cliente_id']) ? (int)$actual['cliente_id'] : 0;
  $oldDomTxt    = trim((string)($actual['domicilio'] ?? ''));

  $clienteAsignadoAhora = false;
  if ($hasClienteId) {
    $clienteAsignadoAhora =
      ($oldClienteId <= 0) &&
      ($clienteIdParsed !== null) &&
      ($clienteIdParsed > 0);
  }

  $horaLlegadaActual = $actual['hora_llegada'];
  $tiempoNotaActual  = $actual['tiempo_en_nota'];

  // Flags política
  $changedFechaReal = ($hasFechaCita && $oldFecha !== (string)($fechaNueva ?? ''));
  $changedDomReal = false;

  $camposEditadosNotif = [];

  // ---- NOTIFICACIÓN DB ----
  // ---- fecha/hora de cita ----
  $oldFechaNorm = normalize_mysql_datetime($actual['fecha_cita'] ?? null);
  $newFechaNorm = $hasFechaCita ? $fechaNueva : $oldFechaNorm;

  if ($hasFechaCita && $oldFechaNorm !== $newFechaNorm) {
    $oldDate = dt_date_part($oldFechaNorm);
    $newDate = dt_date_part($newFechaNorm);

    $oldTime = dt_time_part($oldFechaNorm);
    $newTime = dt_time_part($newFechaNorm);

    if ($oldDate !== $newDate) {
      $camposEditadosNotif[] = 'fecha de cita';
    }
    if ($oldTime !== $newTime) {
      $camposEditadosNotif[] = 'hora de cita';
    }
  }

  // ---- descripción ----
  if ($descripcion !== null) {
    $oldDescNorm = normalize_text_nullable($actual['descripcion'] ?? null);
    $newDescNorm = normalize_text_nullable($descripcion);
    if ($oldDescNorm !== $newDescNorm) {
      $camposEditadosNotif[] = 'descripción';
    }
  }

  // ---- límite de tiempo ----
  if ($hasLimiteTiempo && $limiteTiempoReq !== $oldLimite) {
    $camposEditadosNotif[] = 'límite de tiempo';
  }

  if ($hasDomicilio) {
    $changedDomReal = ($oldDomTxt !== trim((string)($domicilioParsed ?? '')));
  }

  $wantsStartRoute = ($hasRutaIniciada && $rutaIniciadaReq === 1);
  $startedRouteNow = ($wantsStartRoute && $rutaIniciadaActual === 0);

  if ($startedRouteNow) {
    $reporteroNombreNotif = trim((string)($actual['reportero'] ?? ''));
    $mensajeNotif = $reporteroNombreNotif !== ''
      ? "{$reporteroNombreNotif} ha iniciado su ruta."
      : "El reportero ha iniciado su ruta.";

    $stmtNotif = $pdo->prepare("
      INSERT INTO admin_notificaciones (
        tipo,
        noticia_id,
        reportero_id,
        mensaje,
        dedupe_key,
        created_at
      )
      VALUES (
        'inicio_ruta',
        :noticia_id,
        :reportero_id,
        :mensaje,
        :dedupe_key,
        NOW()
      )
      ON DUPLICATE KEY UPDATE id = id
    ");

    $stmtNotif->execute([
      ':noticia_id'   => $noticiaId,
      ':reportero_id' => $repIdNoticia > 0 ? $repIdNoticia : null,
      ':mensaje'      => $mensajeNotif,
      ':dedupe_key'   => "inicio_ruta:{$noticiaId}",
    ]);
  }

  // -------------------- VALIDACION RANGO (anti-choques) --------------------
  $pendienteActual = (int)($actual['pendiente'] ?? 0);

  $fechaFinal = $hasFechaCita
      ? $fechaNueva
      : normalize_mysql_datetime($actual['fecha_cita'] ?? null);

  $limiteFinal = $hasLimiteTiempo ? (int)$limiteTiempoReq : $oldLimite;

  $debeValidarRango =
      ($pendienteActual === 1) &&
      ($repIdNoticia > 0) &&
      ($fechaFinal !== null) &&
      ($hasFechaCita || $hasLimiteTiempo);

  if ($debeValidarRango) {
    // lock reportero para serializar cambios de agenda
    $lockRep = $pdo->prepare("SELECT id FROM reporteros WHERE id = ? FOR UPDATE");
    $lockRep->execute([$repIdNoticia]);
    if (!$lockRep->fetchColumn()) {
      $pdo->rollBack();
      echo json_encode(['success' => false, 'message' => 'Reportero no existe']);
      exit;
    }

    $dtStart = new DateTime($fechaFinal);
    $newStart = $dtStart->format('Y-m-d H:i:s');
    $newEnd   = (clone $dtStart)->modify('+' . $limiteFinal . ' minutes')->format('Y-m-d H:i:s');

    $chk = $pdo->prepare("
      SELECT
        id, noticia, fecha_cita,
        IFNULL(limite_tiempo_minutos, 60) AS limite,
        DATE_ADD(fecha_cita, INTERVAL IFNULL(limite_tiempo_minutos, 60) MINUTE) AS fecha_fin
      FROM noticias
      WHERE reportero_id = ?
        AND pendiente = 1
        AND fecha_cita IS NOT NULL
        AND id <> ?
        AND fecha_cita < ?
        AND DATE_ADD(fecha_cita, INTERVAL IFNULL(limite_tiempo_minutos, 60) MINUTE) > ?
      ORDER BY fecha_cita ASC
      LIMIT 1
    ");
    $chk->execute([$repIdNoticia, $noticiaId, $newEnd, $newStart]);
    $conf = $chk->fetch(PDO::FETCH_ASSOC);

    if ($conf) {
      $pdo->rollBack();
      http_response_code(409);
      echo json_encode([
        'success' => false,
        'code'    => 'cita_ocupada',
        'message' => 'El reportero ya cuenta con una cita a esta fecha / hora',
        'data'    => [
          'noticia_id' => (int)$conf['id'],
          'noticia'    => (string)$conf['noticia'],
          'fecha_cita' => (string)$conf['fecha_cita'],
          'fecha_fin'  => (string)$conf['fecha_fin'],
          'limite'     => (int)$conf['limite'],
        ],
      ]);
      exit;
    }
  }

  // -------------------- BUILD UPDATES --------------------
  $updates = [];
  $params  = [':id' => $noticiaId];

  // ========================= ADMIN =========================
  if ($role === 'admin') {
    if ($hasClienteId) {
      if ($clienteIdParsed === null) {
        $updates[] = "cliente_id = NULL";
        $updates[] = "domicilio = NULL";
      } else {
        if ($clienteIdParsed !== $oldClienteId) {
          $updates[] = "cliente_id = :cliente_id";
          $params[':cliente_id'] = $clienteIdParsed;
        }
      }
    }

    if ($hasDomicilio && !($hasClienteId && $clienteIdParsed === null)) {
      $newDomTxt = trim((string)($domicilioParsed ?? ''));
      if ($newDomTxt !== $oldDomTxt) {
        $updates[] = "domicilio = :domicilio";
        $params[':domicilio'] = $domicilioParsed;
      }
    }

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
      if ($changedFechaReal) {
        $updates[] = "fecha_cita_anterior = :fecha_anterior";
        $params[':fecha_anterior'] = ($actual['fecha_cita'] ?? null);

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
      $pdo->rollBack();
      echo json_encode(['success' => false, 'message' => 'No tienes permiso para cambiar el título']);
      exit;
    }

    if ($descripcion !== null) {
      $descVacia = ($oldDesc === null || trim((string)$oldDesc) === '');
      if (!$descVacia) {
        $pdo->rollBack();
        echo json_encode(['success' => false, 'message' => 'La descripción ya fue capturada y no se puede modificar']);
        exit;
      }
      if (trim((string)$descripcion) === '') {
        $pdo->rollBack();
        echo json_encode(['success' => false, 'message' => 'La descripción no puede quedar vacía']);
        exit;
      }

      $updates[] = "descripcion = :descripcion";
      $params[':descripcion'] = $descripcion;
    }

    if ($tipoDeNota !== null && $tipoDeNota !== $oldTipo) {
      $updates[] = "tipo_de_nota = :tipo_de_nota";
      $params[':tipo_de_nota'] = $tipoDeNota;
    }

    if ($hasFechaCita) {
      if ($changedFechaReal) {
        if ($cambios >= 2) {
          $pdo->rollBack();
          echo json_encode(['success' => false, 'message' => 'Límite alcanzado: ya no puedes cambiar la fecha de cita']);
          exit;
        }

        if (!empty($actual['fecha_cita'])) {
          $updates[] = "fecha_cita_anterior = :fecha_anterior";
          $params[':fecha_anterior'] = ($actual['fecha_cita'] ?? null);
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
  if ($hasLimiteTiempo && $limiteTiempoReq !== $oldLimite) {
    $updates[] = "limite_tiempo_minutos = :limite_tiempo_minutos";
    $params[':limite_tiempo_minutos'] = $limiteTiempoReq;
  }

  // ========================= RUTA INICIADA =========================
  if ($startedRouteNow) {
    $updates[] = "ruta_iniciada = 1";
    $updates[] = "ruta_iniciada_at = COALESCE(ruta_iniciada_at, NOW())";
  }

  // ========================= TIEMPO EN NOTA =========================
  if ($hasTiempoNota) {
    if ($horaLlegadaActual === null || trim((string)$horaLlegadaActual) === '') {
      $pdo->rollBack();
      echo json_encode(['success' => false, 'message' => 'Aún no se ha finalizado la ruta para cronometrar nota']);
      exit;
    }
    if ($tiempoNotaReq <= 0) {
      $pdo->rollBack();
      echo json_encode(['success' => false, 'message' => 'tiempo_en_nota inválido']);
      exit;
    }

    if ($tiempoNotaActual !== null && trim((string)$tiempoNotaActual) !== '') {
      if ((int)$tiempoNotaActual !== (int)$tiempoNotaReq) {
        $pdo->rollBack();
        echo json_encode(['success' => false, 'message' => 'El tiempo en nota ya fue registrado']);
        exit;
      }
      // Idempotente
    } else {
      $updates[] = "tiempo_en_nota = :tiempo_en_nota";
      $params[':tiempo_en_nota'] = $tiempoNotaReq;
    }
  }

  $wantsTiempoNota = $hasTiempoNota;

  $actorNombre = trim((string)($user['nombre'] ?? ''));
  if ($actorNombre === '' && $userId > 0) {
    $qActor = $pdo->prepare("SELECT nombre FROM reporteros WHERE id = ? LIMIT 1");
    $qActor->execute([$userId]);
    $actorNombre = trim((string)($qActor->fetchColumn() ?: ''));
  }
  if ($actorNombre === '') {
    $actorNombre = ($role === 'admin') ? 'Un administrador' : 'Un reportero';
  }

  // Sin cambios
  if (empty($updates)) {
    if (($wantsStartRoute && $rutaIniciadaActual === 1) ||
        ($wantsTiempoNota && $tiempoNotaActual !== null && trim((string)$tiempoNotaActual) !== '' && (int)$tiempoNotaActual === (int)$tiempoNotaReq)) {

      $stmt2 = $pdo->prepare("
        SELECT
          n.id, n.noticia, COALESCE(n.tipo_de_nota,'Nota') AS tipo_de_nota,
          n.descripcion, n.cliente_id, n.domicilio, n.reportero_id, n.fecha_cita,
          n.pendiente, n.ultima_mod, n.ruta_iniciada, n.ruta_iniciada_at,
          n.tiempo_en_nota, n.limite_tiempo_minutos,
          COALESCE(NULLIF(TRIM(r.nombre_pdf), ''), r.nombre) AS reportero
        FROM noticias n
        LEFT JOIN reporteros r ON n.reportero_id = r.id
        WHERE n.id = ?
        LIMIT 1
      ");
      $stmt2->execute([$noticiaId]);
      $row = $stmt2->fetch(PDO::FETCH_ASSOC);

      $pdo->commit();

      echo json_encode([
        'success' => true,
        'message' => 'Sin cambios (idempotente)',
        'data' => $row,
      ]);
      exit;
    }

    $pdo->rollBack();
    echo json_encode(['success' => false, 'message' => 'No hay cambios para guardar']);
    exit;
  }

  // Ultima mod
  $updates[] = "ultima_mod = :ultima_mod";
  $params[':ultima_mod'] = $ultimaMod;

  // Ejecuta UPDATE
  $sqlUp = "UPDATE noticias SET " . implode(", ", $updates) . " WHERE id = :id LIMIT 1";
  $stmtUp = $pdo->prepare($sqlUp);
  $stmtUp->execute($params);

  if (!empty($camposEditadosNotif)) {
    $camposTxt = join_campos_es($camposEditadosNotif);

    $mensajeEdit = "{$actorNombre} modificó {$camposTxt}.";
    // Si quieres incluir el título:
    // $tituloNotif = trim((string)($actual['noticia'] ?? ''));
    // $mensajeEdit = "{$actorNombre} modificó {$camposTxt} en la noticia '{$tituloNotif}'.";

    $stmtNotifEdit = $pdo->prepare("
      INSERT INTO admin_notificaciones (
        tipo,
        noticia_id,
        reportero_id,
        mensaje,
        dedupe_key,
        created_at
      ) VALUES (
        'edicion_noticia',
        :noticia_id,
        :reportero_id,
        :mensaje,
        NULL,
        NOW()
      )
    ");

    $stmtNotifEdit->execute([
      ':noticia_id'   => $noticiaId,
      ':reportero_id' => $userId > 0 ? $userId : null,
      ':mensaje'      => $mensajeEdit,
    ]);                                                                                                                                                                                                                                                                                                                                     
  }

  // Trae row final
  $stmt3 = $pdo->prepare("
    SELECT
      n.id,
      n.noticia,
      COALESCE(n.tipo_de_nota, 'Nota') AS tipo_de_nota,
      n.descripcion,
      n.cliente_id,
      c.nombre   AS cliente,
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
      n.ultima_mod,
      n.ruta_iniciada,
      n.ruta_iniciada_at,
      n.tiempo_en_nota,
      n.limite_tiempo_minutos
    FROM noticias n
    LEFT JOIN reporteros r ON n.reportero_id = r.id
    LEFT JOIN clientes  c ON n.cliente_id  = c.id
    WHERE n.id = ?
    LIMIT 1
  ");
  $stmt3->execute([$noticiaId]);
  $row = $stmt3->fetch(PDO::FETCH_ASSOC);

  $pdo->commit();

  // -------------------- MAIL (POLÍTICA) --------------------
  $mailStatus = 'skipped';
  $mailError  = null;
  $mailTo     = null;

  $mailType = null; // route_started | cliente_assigned | rescheduled | domicilio_changed

  if ($startedRouteNow) { $mailType = 'route_started';
  } elseif ($clienteAsignadoAhora) { $mailType = 'cliente_assigned';
  } elseif ($changedFechaReal) { $mailType = 'rescheduled';
  } elseif ($changedDomReal) { $mailType = 'domicilio_changed'; }

  try {
    $finalClienteId = !empty($row['cliente_id']) ? (int)$row['cliente_id'] : null;

    if ($mailType === null) {
      $mailStatus = 'skipped_no_event';
    } elseif ($finalClienteId === null) {
      $mailStatus = 'skipped_no_cliente';
    } else {
      $stmtC = $pdo->prepare("SELECT nombre, correo FROM clientes WHERE id = ? LIMIT 1");
      $stmtC->execute([$finalClienteId]);
      $c = $stmtC->fetch(PDO::FETCH_ASSOC) ?: [];

      $nombreCliente = trim((string)($c['nombre'] ?? ''));
      $correoCliente = trim((string)($c['correo'] ?? ''));
      $mailTo = $correoCliente;

      if ($correoCliente === '') {
        $mailStatus = 'skipped_empty_email';
      } elseif (!filter_var($correoCliente, FILTER_VALIDATE_EMAIL)) {
        $mailStatus = 'skipped_invalid_email';
      } elseif (!is_array($mailCfg) || trim((string)($mailCfg['password'] ?? '')) === '') {
        $mailStatus = 'skipped_smtp_not_configured';
      } else {
        $tituloNoticia = (string)($row['noticia'] ?? 'Noticia');
        $domTxt = trim((string)($row['domicilio'] ?? ''));
        $domTxt = ($domTxt !== '') ? $domTxt : 'Sin domicilio';
        $citaNuevaTxt = fmt_dt_mx_long($row['fecha_cita'] ?? null);
        $reporteroTxt = trim((string)($row['reportero'] ?? ''));

        $subject   = '';
        $bodyText  = '';
        $bodyHtml  = '';

        if ($mailType === 'route_started') {
          $subject  = 'Tu reportero ya está en camino - Televisión Por Cable Tepa';

          $bodyText =
            "Hola" . ($nombreCliente !== '' ? " {$nombreCliente}" : "") . ",\n\n" .
            "Tu reportero ya está en camino. Recuerda estar en el lugar y hora acordada.\n\n" .
            "Asunto: {$tituloNoticia}\n" .
            "Cita: {$citaNuevaTxt}\n" .
            "Domicilio: {$domTxt}\n" .
            ($reporteroTxt !== '' ? "Reportero: {$reporteroTxt}\n" : "") .
            "Estatus: En trayecto\n\n" .
            "Televisión Por Cable Tepa";

          $details = [
            ['Asunto', $tituloNoticia],
            ['Cita', $citaNuevaTxt],
            ['Domicilio', $domTxt],
          ];
          if ($reporteroTxt !== '') $details[] = ['Reportero', $reporteroTxt];
          $details[] = ['Estatus', 'En trayecto'];

          $bodyHtml = email_template_html([
            'brand' => 'Televisión Por Cable Tepa',
            'title' => 'Reporte en camino',
            'preheader' => 'El reportero ya va en camino. Revisa los detalles de tu cita.',
            'greeting' => 'Hola' . ($nombreCliente !== '' ? " {$nombreCliente}" : ''),
            'intro' => 'Tu reportero ya está en camino. Recuerda estar en el lugar y hora acordada.',
            'details' => $details,
            'footer' => 'Televisión Por Cable Tepa',
          ]);

        } elseif ($mailType === 'cliente_assigned') {
          $subject = 'Has Agendado tu Cita - Televisión Por Cable Tepa';

          $bodyText =
            "Hola" . ($nombreCliente !== '' ? " {$nombreCliente}" : "") . ",\n\n" .
            "Tu cita ha sido agendada exitosamente.\n\n" .
            "Asunto: {$tituloNoticia}\n" .
            "Cita: {$citaNuevaTxt}\n" .
            "Domicilio: {$domTxt}\n" .
            ($reporteroTxt !== '' ? "Reportero: {$reporteroTxt}\n" : "") .
            "\nTelevisión Por Cable Tepa";

          $details = [
            ['Asunto', $tituloNoticia],
            ['Cita', $citaNuevaTxt],
            ['Domicilio', $domTxt],
          ];
          if ($reporteroTxt !== '') {
            $details[] = ['Reportero', $reporteroTxt];
          }
          $details[] = ['Estatus', 'Agendada'];

          $bodyHtml = email_template_html([
            'brand' => 'Televisión Por Cable Tepa',
            'title' => 'Cita agendada',
            'preheader' => 'Tu cita ha sido asignada y registrada.',
            'greeting' => 'Hola' . ($nombreCliente !== '' ? " {$nombreCliente}" : ''),
            'intro' => 'Tu cita ha sido agendada exitosamente. Te compartimos los detalles:',
            'details' => $details,
            'footer' => 'Televisión Por Cable Tepa',
          ]);
        } elseif ($mailType === 'rescheduled') {
          $citaOldTxt = fmt_dt_mx_long($actual['fecha_cita'] ?? null);
          $subject = 'Tu cita fue actualizada - Televisión Por Cable Tepa';

          $bodyText =
            "Hola" . ($nombreCliente !== '' ? " {$nombreCliente}" : "") . ",\n\n" .
            "Tu cita fue actualizada.\n\n" .
            "Asunto: {$tituloNoticia}\n" .
            "Antes: {$citaOldTxt}\n" .
            "Ahora: {$citaNuevaTxt}\n" .
            "Domicilio: {$domTxt}\n\n" .
            ($reporteroTxt !== '' ? "Reportero: {$reporteroTxt}\n" : "") .
            "\nTelevisión Por Cable Tepa";

          $details = [
            ['Asunto', $tituloNoticia],
            ['Antes', $citaOldTxt],
            ['Ahora', $citaNuevaTxt],
            ['Domicilio', $domTxt],
            $reporteroTxt !== '' ? ['Reportero', $reporteroTxt] : null,
            ['Estatus', 'Reprogramada'],
          ];

          $bodyHtml = email_template_html([
            'brand' => 'Televisión Por Cable Tepa',
            'title' => 'Cita actualizada',
            'preheader' => 'Se actualizó la fecha de tu cita.',
            'greeting' => 'Hola' . ($nombreCliente !== '' ? " {$nombreCliente}" : ''),
            'intro' => 'Se actualizó la fecha de tu cita. Te compartimos el cambio:',
            'details' => $details,
            'footer' => 'Televisión Por Cable Tepa',
          ]);

        } else { // domicilio_changed
          $domOld = trim((string)($actual['domicilio'] ?? ''));
          $domOld = ($domOld !== '') ? $domOld : 'Sin domicilio';

          $subject = 'Se actualizó el domicilio de tu cita - Televisión Por Cable Tepa';

          $bodyText =
            "Hola" . ($nombreCliente !== '' ? " {$nombreCliente}" : "") . ",\n\n" .
            "Se actualizó el domicilio de tu cita.\n\n" .
            "Asunto: {$tituloNoticia}\n" .
            "Cita: {$citaNuevaTxt}\n" .
            "Antes: {$domOld}\n" .
            "Ahora: {$domTxt}\n\n" .
            ($reporteroTxt !== '' ? "Reportero: {$reporteroTxt}\n" : "") .
            "\nTelevisión Por Cable Tepa";

          $details = [
            ['Asunto', $tituloNoticia],
            ['Cita', $citaNuevaTxt],
            ['Domicilio anterior', $domOld],
            ['Domicilio nuevo', $domTxt],
            $reporteroTxt !== '' ? ['Reportero', $reporteroTxt] : null,
            ['Estatus', 'Actualización de domicilio'],
          ];

          $bodyHtml = email_template_html([
            'brand' => 'Televisión Por Cable Tepa',
            'title' => 'Domicilio actualizado',
            'preheader' => 'Se actualizó el domicilio de tu cita.',
            'greeting' => 'Hola' . ($nombreCliente !== '' ? " {$nombreCliente}" : ''),
            'intro' => 'Se actualizó el domicilio de tu cita. Revisa los datos:',
            'details' => $details,
            'footer' => 'Televisión Por Cable Tepa',
          ]);
        }

        smtp_send_mail($mailCfg, $correoCliente, $nombreCliente, $subject, $bodyText, $bodyHtml);
        $mailStatus = 'sent';
      }
    }
  } catch (Throwable $e) {
    $mailStatus = 'error';
    $mailError  = $e->getMessage();
    error_log("MAIL update_noticia error noticia_id={$noticiaId}: " . $mailError);
  }

  $out = ['success' => true, 'data' => $row];
  if ($debugMail) {
    $out['mail_status'] = $mailStatus;
    $out['mail_to'] = $mailTo;
    $out['mail_error'] = $mailError;
    $out['mail_type'] = $mailType;
  }

  echo json_encode($out);
  exit;

} catch (Throwable $e) {
  if ($pdo->inTransaction()) {
    try { $pdo->rollBack(); } catch (Throwable $_) {}
  }

  http_response_code(500);
  echo json_encode([
    'success' => false,
    'message' => 'Error al actualizar',
    'error' => $e->getMessage(),
  ]);
  exit;
}
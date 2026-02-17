<?php
declare(strict_types=1);

ini_set('display_errors', '0');   // NO imprimir errores en salida
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');

require __DIR__ . '/config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
  http_response_code(405);
  echo json_encode(['success' => false, 'message' => 'Método no permitido']);
  exit;
}

// ✅ debug flag por querystring
$debug = isset($_GET['debug_fcm']) && $_GET['debug_fcm'] === '1';

// ✅ Acepta JSON o x-www-form-urlencoded
$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);

$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

// Helpers
$noticia     = isset($in['noticia']) ? trim((string)$in['noticia']) : '';
$descripcion = isset($in['descripcion']) ? trim((string)$in['descripcion']) : '';
$domicilio   = isset($in['domicilio']) ? trim((string)$in['domicilio']) : '';
$fechaCita   = isset($in['fecha_cita']) ? trim((string)$in['fecha_cita']) : '';
$tipoDeNota = isset($in['tipo_de_nota']) ? trim((string)$in['tipo_de_nota']) : 'Nota';
if ($tipoDeNota === '') $tipoDeNota = 'Nota';

$allowedTipos = ['Nota', 'Entrevista'];
if (!in_array($tipoDeNota, $allowedTipos, true)) {
  echo json_encode(['success' => false, 'message' => 'tipo_de_nota inválido (usa Nota o Entrevista)']);
  exit;
}

// reportero_id opcional (null si no viene o viene vacío/0)
$reporteroId = null;
if (isset($in['reportero_id']) && $in['reportero_id'] !== '' && $in['reportero_id'] !== null) {
  $tmp = (int)$in['reportero_id'];
  if ($tmp > 0) $reporteroId = $tmp;
}

// Validación principal
if ($noticia === '') {
  echo json_encode(['success' => false, 'message' => 'El campo noticia es obligatorio']);
  exit;
}

// Normaliza valores opcionales
$descripcionValue = ($descripcion !== '') ? $descripcion : null;
$domicilioValue   = ($domicilio !== '') ? $domicilio : null;

// ✅ Normaliza fecha (acepta "2025-12-29T18:10:00" o "2025-12-29 18:10:00")
$fechaCitaValue = null;
if ($fechaCita !== '') {
  $fechaCita = str_replace('T', ' ', $fechaCita);

  // intenta: Y-m-d H:i:s
  $dt = DateTime::createFromFormat('Y-m-d H:i:s', $fechaCita);
  if (!$dt) {
    // intenta: Y-m-d H:i
    $dt = DateTime::createFromFormat('Y-m-d H:i', $fechaCita);
  }

  if (!$dt) {
    echo json_encode([
      'success' => false,
      'message' => 'fecha_cita inválida. Usa "YYYY-MM-DD HH:MM:SS" o "YYYY-MM-DDTHH:MM:SS".'
    ]);
    exit;
  }

  $fechaCitaValue = $dt->format('Y-m-d H:i:s');
}

try {
  $sql = "
    INSERT INTO noticias (
      noticia, tipo_de_nota, descripcion, cliente_id, domicilio, reportero_id, fecha_cita, pendiente
    ) VALUES (
      :noticia, :tipo_de_nota, :descripcion, NULL, :domicilio, :reportero_id, :fecha_cita, 1
    )
  ";

  $stmt = $pdo->prepare($sql);
  $stmt->execute([
    ':noticia'      => $noticia,
    ':tipo_de_nota' => $tipoDeNota,
    ':descripcion'  => $descripcionValue,
    ':domicilio'    => $domicilioValue,
    ':reportero_id' => $reporteroId,
    ':fecha_cita'   => $fechaCitaValue,
  ]);

  $newId = (int)$pdo->lastInsertId();

  // ----------- Notificación FCM (si existe fcm.php; no rompe si falla) -----------
  $fcmResult = null;
  $fcmError  = null;
  $topic     = null;

  try {
    $fcmPath = __DIR__ . '/fcm.php';
    if (!file_exists($fcmPath)) {
      throw new Exception("FCM: no existe fcm.php en {$fcmPath}");
    }

    require_once $fcmPath;

    $topic = ($reporteroId === null)
      ? 'rol_reportero'
      : ('reportero_' . $reporteroId);

    $fcmResult = fcm_send_topic([
      'topic' => $topic,
      'title' => ($reporteroId === null) ? 'Nueva noticia disponible' : 'Nueva noticia',
      'body'  => $noticia,
      'data'  => [
        'tipo'       => ($reporteroId === null) ? 'noticia_sin_asignar' : 'nueva_noticia',
        'noticia_id' => (string)$newId,
      ],
    ]);

    error_log("FCM send topic={$topic} result=" . json_encode($fcmResult));
  } catch (Throwable $e) {
    $fcmError = $e->getMessage();
    error_log("FCM error: " . $fcmError);
  }

  // ✅ Debug mode: devuelve también el resultado de FCM
  if ($debug) {
    echo json_encode([
      'success' => true,
      'message' => 'Noticia creada + debug FCM',
      'id'      => $newId,
      'topic'   => $topic,
      'fcm'     => $fcmResult,   // {code, resp, err}
      'fcm_error' => $fcmError,  // string o null
    ]);
    exit;
  }

  // Respuesta normal
  echo json_encode([
    'success' => true,
    'message' => 'Noticia creada correctamente',
    'id'      => $newId,
  ]);
  exit;

} catch (Throwable $e) {
  http_response_code(500);
  error_log("crear_noticia.php error: " . $e->getMessage());

  echo json_encode([
    'success' => false,
    'message' => 'Error al crear noticia',
  ]);
  exit;
}

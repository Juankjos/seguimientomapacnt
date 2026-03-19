<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

require __DIR__ . '/config.php';
require __DIR__ . '/require_auth.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

// INPUT (JSON o FORM)
$raw  = file_get_contents('php://input');
$json = json_decode($raw ?: '', true);
$in = (is_array($json) && json_last_error() === JSON_ERROR_NONE) ? $json : $_POST;

// AUTH
$user = require_auth($pdo, is_array($in) ? $in : []);
$role = (string)($user['role'] ?? '');

if ($role !== 'admin') {
    http_response_code(403);
    echo json_encode(['success' => false, 'message' => 'Solo admin puede reasignar noticias']);
    exit;
}

$idsRaw = $in['noticia_ids'] ?? [];
$targetRaw = $in['nuevo_reportero_id'] ?? '';

// noticia_ids puede venir como array o como JSON string
if (is_string($idsRaw)) {
    $decoded = json_decode($idsRaw, true);
    $ids = is_array($decoded) ? $decoded : [];
} elseif (is_array($idsRaw)) {
    $ids = $idsRaw;
} else {
    $ids = [];
}

if (count($ids) === 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_ids inválido']);
    exit;
}

$ids = array_values(array_filter(array_map('intval', $ids), fn($v) => $v > 0));
if (count($ids) === 0) {
    echo json_encode(['success' => false, 'message' => 'noticia_ids vacío']);
    exit;
}

$nuevoReporteroId = null;
$nombreNuevoReportero = '';

if ($targetRaw !== '' && (int)$targetRaw > 0) {
    $nuevoReporteroId = (int)$targetRaw;

    $st = $pdo->prepare("SELECT id, role, nombre FROM reporteros WHERE id = ? LIMIT 1");
    $st->execute([$nuevoReporteroId]);
    $u = $st->fetch(PDO::FETCH_ASSOC);

    if (!$u || ($u['role'] ?? '') !== 'reportero') {
        echo json_encode(['success' => false, 'message' => 'nuevo_reportero_id inválido']);
        exit;
    }

    $nombreNuevoReportero = trim((string)($u['nombre'] ?? ''));
}

try {
    $pdo->beginTransaction();

    $placeholders = implode(',', array_fill(0, count($ids), '?'));

    // Lock de noticias
    $sqlSel = "
        SELECT
            n.id,
            n.noticia,
            n.reportero_id
        FROM noticias n
        WHERE n.id IN ($placeholders)
        FOR UPDATE
    ";
    $stmtSel = $pdo->prepare($sqlSel);
    $stmtSel->execute($ids);
    $rows = $stmtSel->fetchAll(PDO::FETCH_ASSOC);

    if (!$rows) {
        $pdo->rollBack();
        echo json_encode(['success' => false, 'message' => 'No se encontraron noticias']);
        exit;
    }

    $idsACambiar = [];
    $notificaciones = [];

    foreach ($rows as $row) {
        $nid = (int)$row['id'];
        $titulo = trim((string)($row['noticia'] ?? 'Noticia'));
        $actualRid = !empty($row['reportero_id']) ? (int)$row['reportero_id'] : null;

        // Desasignar
        if ($nuevoReporteroId === null) {
        if ($actualRid !== null) {
            $idsACambiar[] = $nid;
            $notificaciones[] = [
            'tipo' => 'liberacion_noticia',
            'noticia_id' => $nid,
            'reportero_id' => null,
            'mensaje' => "{$titulo} se encuentra libre para asignación.",
            ];
        }
        continue;
        }

        if ($actualRid !== $nuevoReporteroId) {
        $idsACambiar[] = $nid;
        $notificaciones[] = [
            'tipo' => 'asignacion_noticia',
            'noticia_id' => $nid,
            'reportero_id' => $nuevoReporteroId,
            'mensaje' => "{$titulo} ha sido asignada a {$nombreNuevoReportero}.",
        ];
        }
    }

    if (count($idsACambiar) > 0) {
        $ph2 = implode(',', array_fill(0, count($idsACambiar), '?'));

        if ($nuevoReporteroId === null) {
            $sqlUp = "UPDATE noticias SET reportero_id = NULL, ultima_mod = NOW() WHERE id IN ($ph2)";
            $stmtUp = $pdo->prepare($sqlUp);
            $stmtUp->execute($idsACambiar);
        } else {
            $sqlUp = "UPDATE noticias SET reportero_id = ?, ultima_mod = NOW() WHERE id IN ($ph2)";
            $stmtUp = $pdo->prepare($sqlUp);
            $stmtUp->execute(array_merge([$nuevoReporteroId], $idsACambiar));
        }

        $stmtNotif = $pdo->prepare("
        INSERT INTO admin_notificaciones (
            tipo,
            noticia_id,
            reportero_id,
            mensaje,
            dedupe_key,
            created_at
        ) VALUES (
            :tipo,
            :noticia_id,
            :reportero_id,
            :mensaje,
            NULL,
            NOW()
        )
        ");

        foreach ($notificaciones as $n) {
        $stmtNotif->execute([
            ':tipo' => $n['tipo'],
            ':noticia_id' => $n['noticia_id'],
            ':reportero_id' => $n['reportero_id'],
            ':mensaje' => $n['mensaje'],
        ]);
        }
    }

    $pdo->commit();

    echo json_encode([
        'success' => true,
        'message' => 'Noticias reasignadas',
        'updated' => count($idsACambiar),
    ]);
    exit;

} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        try { $pdo->rollBack(); } catch (Throwable $_) {}
    }

    http_response_code(500);
    error_log("reassign_noticias.php error: " . $e->getMessage());
    echo json_encode([
        'success' => false,
        'message' => 'Error al reasignar',
        'error' => $e->getMessage(),
    ]);
    exit;
}

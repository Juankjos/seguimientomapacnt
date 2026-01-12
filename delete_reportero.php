<?php
require 'config.php';

header('Content-Type: application/json; charset=utf-8');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['success' => false, 'message' => 'Método no permitido']);
    exit;
}

$reporteroId = isset($_POST['reportero_id']) ? intval($_POST['reportero_id']) : 0;
if ($reporteroId <= 0) {
    echo json_encode(['success' => false, 'message' => 'reportero_id inválido']);
    exit;
}

try {
    // (Opcional) valida que no sea admin (por seguridad)
    $stmt0 = $pdo->prepare("SELECT role FROM reporteros WHERE id = ? LIMIT 1");
    $stmt0->execute([$reporteroId]);
    $u = $stmt0->fetch();
    if (!$u) {
        echo json_encode(['success' => false, 'message' => 'No existe el reportero']);
        exit;
    }
    if ($u['role'] === 'admin') {
        $stmtCount = $pdo->query("SELECT COUNT(*) AS c FROM reporteros WHERE role='admin'");
        $c = (int)($stmtCount->fetch()['c'] ?? 0);
        if ($c <= 1) {
            echo json_encode(['success' => false, 'message' => 'No se puede borrar el último admin']);
            exit;
        }
    }

    $stmt = $pdo->prepare("DELETE FROM reporteros WHERE id = ? LIMIT 1");
    $stmt->execute([$reporteroId]);

    echo json_encode(['success' => true, 'message' => 'Usuario borrado']);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['success' => false, 'message' => 'Error al borrar reportero', 'error' => $e->getMessage()]);
}

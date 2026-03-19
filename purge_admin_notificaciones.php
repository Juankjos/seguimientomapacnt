<?php
declare(strict_types=1);

ini_set('display_errors', '0');
ini_set('log_errors', '1');
ini_set('error_log', __DIR__ . '/php-error.log');
error_reporting(E_ALL);

require __DIR__ . '/config.php';

try {
    $stmt = $pdo->prepare("
        DELETE FROM admin_notificaciones
        WHERE created_at < (NOW() - INTERVAL 1 DAY)
    ");
    $stmt->execute();

    echo "OK - eliminadas: " . $stmt->rowCount() . PHP_EOL;
} catch (Throwable $e) {
    error_log("purge_admin_notificaciones.php error: " . $e->getMessage());
    http_response_code(500);
    echo "ERROR" . PHP_EOL;
}
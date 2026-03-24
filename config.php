<?php
// --------- CORS ---------
date_default_timezone_set('America/Mexico_City');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Origin, X-Requested-With, Content-Type, Accept, Authorization");
header("Access-Control-Max-Age: 86400");

// Preflight
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$envFile = __DIR__ . '/.env';
if (file_exists($envFile)) {
    $lines = file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || str_starts_with($line, '#')) continue;
        [$k, $v] = array_map('trim', explode('=', $line, 2));
        if ($k !== '') putenv("$k=$v");
    }
}

// --------- RESPUESTA JSON ---------
header('Content-Type: application/json; charset=utf-8');

$host    = getenv('DB_HOST');
$port    = getenv('DB_PORT');
$dbname  = getenv('DB_NAME');
$user    = getenv('DB_USER');
$pass    = getenv('DB_PASS');
$charset = getenv('DB_CHARSET') ?: 'utf8mb4';

$dsn = "mysql:host={$host};port={$port};dbname={$dbname};charset={$charset}";

$mailCfg = [
    'host' => getenv('SMTP_HOST'),
    'port' => (int)(getenv('SMTP_PORT')),
    'username' => getenv('SMTP_USER'),
    'password' => getenv('SMTP_PASS'),
    'from_email' => getenv('SMTP_FROM_EMAIL') ?: (getenv('SMTP_USER') ),
    'from_name' => getenv('SMTP_FROM_NAME'),
];

if ($mailCfg['password'] === '') {
    error_log("⚠️ SMTP_PASS vacío: correo deshabilitado hasta configurar .env");
}

try {
    $options = [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,

        // DigitalOcean Managed MySQL normalmente exige SSL:
        // PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT => false,
        // Si tienes CA certificate, mejor úsalo (recomendado) con:
        // PDO::MYSQL_ATTR_SSL_CA => __DIR__ . '/ca-certificate.crt',
    ];

    $pdo = new PDO($dsn, $user, $pass, $options);
    
    // ------------ CAMBIAR SI EL SERVIDOR TIENE DIFERENTE ZONA HORARIA ------------
    $pdo->exec("SET time_zone = '-06:00'");

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Error de conexión a la base de datos',
        'error'   => $e->getMessage(),
    ]);
    exit;
}

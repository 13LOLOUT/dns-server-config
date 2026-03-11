# script para configurar servidor DNS en windows 11
# dominio: reprobados.com
# usa dnscmd = windows 11

$domain = "reprobados.com"

# colores para mensajes
function Write-Ok { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

# verificar que se corra como administrador
function Check-Admin {
    $admin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $admin) {
        Write-Err "necesitas correr este script como administrador"
        exit 1
    }
    Write-Ok "corriendo como administrador"
}

# verificar ip estatica
function Check-StaticIP {
    Write-Info "revisando si hay ip estatica configurada..."

    $adapter = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.InterfaceAlias -notlike "*Loopback*" -and
        $_.PrefixOrigin -eq "Manual"
    } | Select-Object -First 1

    if ($null -eq $adapter) {
        Write-Err "no se encontro ip estatica"
        Write-Info "hay que configurar una antes de continuar"

        $staticIP = Read-Host "ip estatica (ejemplo 192.168.1.100)"
        $prefix   = Read-Host "prefijo de mascara (ejemplo 24)"
        $gateway  = Read-Host "puerta de enlace (ejemplo 192.168.1.1)"

        $iface = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
        Remove-NetIPAddress -InterfaceAlias $iface.Name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceAlias $iface.Name -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $iface.Name -IPAddress $staticIP -PrefixLength $prefix -DefaultGateway $gateway

        Write-Ok "ip estatica $staticIP configurada"
        return $staticIP
    } else {
        Write-Ok "ya tiene ip estatica: $($adapter.IPAddress)"
        return $adapter.IPAddress
    }
}

# habilitar cliente dns y servicio dns en windows 11
function Install-DNSService {
    Write-Info "verificando servicio DNS de Windows..."

    $svc = Get-Service -Name "DNS" -ErrorAction SilentlyContinue

    if ($svc -and $svc.Status -eq "Running") {
        Write-Ok "servicio DNS ya esta corriendo, me lo salto"
    } else {
        Write-Info "habilitando servicio DNS..."
        # en windows 11 habilitamos el cliente dns
        Set-Service -Name "Dnscache" -StartupType Automatic
        Start-Service -Name "Dnscache"
        Write-Ok "servicio DNS client habilitado"
    }
}

# crear zona y registros usando dnscmd
function Configure-Zone {
    param($ip)

    Write-Info "configurando zona $domain con dnscmd..."

    # verificar si dnscmd esta disponible
    $dnscmd = Get-Command dnscmd -ErrorAction SilentlyContinue

    if (-not $dnscmd) {
        Write-Err "dnscmd no disponible, configurando via hosts file como alternativa..."

        # alternativa: agregar entradas al archivo hosts
        $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
        $hostsContent = Get-Content $hostsPath

        if ($hostsContent -notmatch "reprobados.com") {
            Add-Content -Path $hostsPath -Value "`n$ip`t$domain"
            Add-Content -Path $hostsPath -Value "$ip`twww.$domain"
            Write-Ok "entradas agregadas al archivo hosts"
        } else {
            Write-Ok "entradas ya existen en hosts, me las salto"
        }
    } else {
        # crear zona primaria
        dnscmd /zoneadd $domain /primary
        # agregar registro A
        dnscmd /recordadd $domain "@" A $ip
        # agregar registro CNAME para www
        dnscmd /recordadd $domain "www" CNAME "$domain."
        Write-Ok "zona y registros configurados con dnscmd"
    }
}

# pruebas de resolucion
function Run-Tests {
    param($ip)

    Write-Info "ejecutando pruebas..."

    Write-Host ""
    Write-Info "nslookup reprobados.com"
    nslookup $domain

    Write-Host ""
    Write-Info "nslookup www.reprobados.com"
    nslookup "www.$domain"

    Write-Host ""
    Write-Info "ping www.reprobados.com"
    ping www.$domain
}

# --- inicio ---
Write-Host "====================================="
Write-Host " DNS setup - $domain (Windows 11)"
Write-Host "====================================="
Write-Host ""

Check-Admin
$ip = Check-StaticIP
Install-DNSService
Configure-Zone -ip $ip
Run-Tests -ip $ip

Write-Host ""
Write-Ok "todo listo"
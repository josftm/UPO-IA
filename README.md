# Entorno Automatizado — Inteligencia Artificial

Script de instalación masiva y automatizada del entorno de desarrollo para la asignatura de **Inteligencia Artificial** (EPS, Universidad Pablo de Olavide).

## ¿Qué instala?

Dado un rango de IPs, el script se conecta por SSH a cada equipo del aula de forma **asíncrona** e instala:

- Actualización completa del sistema (`apt update` + `apt upgrade`)
- Paquetes base: `openssh-server`, `net-tools`, `curl`
- **Anaconda3** (2024.10-1) — instalación silenciosa en `~/anaconda3`
- Entorno conda **`entornoIA2425`** — creado desde `entornoIA2425.yml`
- Configuración de **Jupyter Notebook** con directorio raíz `~/`
- **anaconda-navigator**

Si algún componente ya está instalado en un equipo, se omite y se notifica al profesor.

## Requisitos

- El equipo del profesor: Ubuntu con acceso por red al aula.
- Los equipos remotos: Ubuntu con SSH activo (`openssh-server`) y usuario con permisos `sudo`.
- Los archivos `install_entorno_IA.sh` y `entornoIA2425.yml` deben estar **en el mismo directorio**.
- `sshpass` — el script lo instala automáticamente si no está disponible.

## Estructura del repositorio

```
IA/
├── install_entorno_IA.sh   # Script principal
├── entornoIA2425.yml       # Definición del entorno conda
└── README.md
```

## Uso

```bash
chmod +x install_entorno_IA.sh
./install_entorno_IA.sh <IP_inicial> <IP_final>
```

**Ejemplo** — instalar en 30 equipos:

```bash
./install_entorno_IA.sh 192.168.1.1 192.168.1.30
```

Al iniciar, el script pide las credenciales SSH **una única vez**:

```
Introduce las credenciales SSH para los equipos remotos:
  Usuario: eps
  Contraseña:
```

La contraseña no se almacena en ningún fichero.

## Salida esperada

```
======================================================
  Instalación masiva del entorno IA
  Rango: 192.168.1.1 → 192.168.1.30  (30 equipos)
  Usuario SSH: eps
  AVISO: Anaconda (~1 GB) y el entorno conda pueden
  tardar 20-40 min por equipo.
======================================================

▶ Lanzando instalación en 192.168.1.1...
▶ Lanzando instalación en 192.168.1.2...
...

⏳ Esperando a que terminen los 30 equipos...

✔ [10:03:42] El equipo con IP 192.168.1.3 ha terminado correctamente (1843s).
  ℹ 192.168.1.3: ya estaba instalado → openssh-server, anaconda3
✔ [10:04:01] El equipo con IP 192.168.1.1 ha terminado correctamente (1901s).
...
```

## Tiempos estimados

| Componente | Tiempo aprox. |
|---|---|
| Paquetes apt | 1-3 min |
| Descarga Miniconda (~100 MB) | 1-3 min (según red) |
| Instalación Miniconda | < 1 min |
| Instalación solver libmamba | 1-2 min |
| Creación entorno conda | 5-10 min |
| anaconda-navigator | 2-5 min |
| **Total estimado** | **10-20 min** |

> Se usa **Miniconda** en lugar de Anaconda (10x menos descarga) y el solver **libmamba** (5-10x más rápido en resolución de dependencias), reduciendo el tiempo total a la mitad aproximadamente.

Al ejecutarse en paralelo, el tiempo total equivale al del equipo más lento.

## Logs

Cada equipo genera su log individual en el equipo del profesor:

```
/tmp/install_ia_logs/install_192_168_1_1.log
```

Los equipos que fallan se consolidan en un único fichero:

```
/tmp/install_ia_logs/errores.log
```

## Entorno conda

El entorno `entornoIA2425` incluye Python 3.9 con las siguientes bibliotecas principales:

- **NumPy**, **Pandas**, **Matplotlib**, **Seaborn** — análisis y visualización de datos
- **Scikit-learn**, **Scikit-image** — machine learning y visión por computador
- **JupyterLab** / **Jupyter Notebook** — entorno interactivo
- **Kneed** — detección de codo en curvas (clustering)

## Seguridad

> El script está diseñado para redes de aula controladas.  
> Para entornos más seguros, se recomienda distribuir una **clave SSH pública** en los equipos y prescindir de `sshpass`.

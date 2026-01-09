# 📰 Noticias CNT
**Gestión y monitoreo de trayectos para cobertura de noticias en campo**

Proyecto para **agendar, asignar y monitorear tareas (noticias)** desde un rol **Administrador** hacia **Agentes (Reporteros)**, integrando:
- 📍 **Mapa con geolocalización** y punto de encuentro (destino)
- 🧭 **Seguimiento de trayecto en tiempo real** (Admin como espectador / Agente como ejecutor)
- 🗓️ **Agenda tipo calendario** (Año / Mes / Día) para ambos roles
- 📊 **Panel de estadísticas** con métricas por **días, semanas, meses y años**
- 🗄️ Persistencia en **base de datos relacional SQL**

---

## ✨ Características principales

### 👤 Roles
- **Administrador**
  - Control de **usuarios** (agregar / editar / eliminar agentes)
  - **Creación y gestión de tareas** (asignar / reasignar / desasignar)
  - **Agenda global** con visibilidad de todas las tareas
  - **Estadísticas** con gráficas y vistas históricas (legado), actuales y futuras
  - Espectador del tracking (no puede finalizar rutas)

- **Agente (Reportero)**
  - Ve y gestiona sus tareas **asignadas o autoasignadas**
  - Puede **tomar tareas sin asignar**
  - Puede editar datos de la tarea (con límites definidos)
  - Inicia y finaliza el **trayecto de ruta**, registrando la **última ubicación**

---

## 🧩 Flujo general (resumen)
1. El **Administrador** crea una tarea (con título obligatorio) y puede:
   - asignarla a un agente, o
   - dejarla sin asignar para que alguien la tome.
2. El **Agente** visualiza tareas asignadas o **toma** una sin asignar.
3. El **Agente** abre el detalle, ajusta información (si aplica) y **comienza ruta**.
4. Se realiza **tracking en tiempo real** hacia el destino.
5. El **Agente finaliza** (o cancela) y se registra **última ubicación + fecha/hora**.
6. La tarea pasa a **Completada**, permanece en BD y se refleja en agenda/estadísticas.
   - Opcional: el agente puede **removerla visualmente** de su lista (sin borrarla de BD).

---

## ✅ Estados de tarea
- **Agendada**
- **En curso**
- **Completada**

---

## 🗓️ Agenda (Calendario)
La agenda se divide en **3 vistas**:
- **Año** → selecciona mes
- **Mes** → marca días con tareas y lista inferior
- **Día** → lista de tareas del día y acceso al detalle

**Visibilidad por rol:**
- Administrador: **todas** las tareas (asignadas y sin asignar), completadas y agendadas
- Agente: solo tareas **asignadas o autoasignadas**, completadas y agendadas

---

## 🧭 Trayecto de ruta (Tracking)
- El **Agente** inicia ruta desde el detalle:
  - Punto **A**: ubicación real geolocalizada
  - Punto **B**: destino definido en mapa (admin o agente)
- Se traza una **línea/ruta** hacia el destino
- El administrador observa el trayecto **en tiempo real** mediante un **socket orquestador**
- El tracking finaliza cuando el agente:
  - **cancela** la ruta, o
  - **finaliza** la ruta (se registra última ubicación + fecha/hora en BD)

---

## 🧑‍💻 UX por Rol

### 🟦 Agente (Reportero)
**Panel de noticias**
- Lista de tareas asignadas/autoasignadas (si existen)

**Tomar noticia**
- Muestra tareas **sin asignar**
- Al tomarla, se refleja en **Panel de noticias** y/o **Agenda**

**Panel de noticia (detalle)**
- Edita:
  - Descripción (si no existe)
  - Fecha y hora de cita (**máximo 2 cambios**)
  - Destino en mapa por coordenadas/puntero (**ilimitado**)
- Mantiene registro de cambios relevantes (descripción / fecha cita / ubicación)

**Agenda**
- Año / Mes / Día → al seleccionar una tarea, redirige al detalle

---

### 🟨 Administrador
**Agenda (inicio)**
- Vista completa de tareas (asignadas y sin asignar)
- Botón para **crear tarea**

**Crear noticia**
- Campos:
  - **Título (obligatorio)**
  - Descripción (opcional)
  - Domicilio (opcional)
  - Asignación a agente (opcional, por defecto sin asignar)

**Gestión Noticias**
- Lista de agentes con contador de tareas
- Reasignación/desasignación:
  - Desasignada → aparece en “Tomar noticia” (Agente) y “Noticias sin asignar” (Admin)

**Noticias sin asignar**
- Lista de tareas libres con opción de asignarlas a un agente

**Estadísticas**
- Gráficas por:
  - Días (incluye sub-vista calendario por día)
  - Semanas (carrusel 4–5 semanas alrededor de la actual)
  - Meses (vista mensual + drilldown a semanas/días)
  - Años (año actual + anteriores/posteriores con drilldown a meses, semanas, días)

---

## 🔐 Autenticación
- Login basado en **token por rol**
- ⚠️ **Token sin expiración** (requisito del sponsor) para mantener sesión activa
- Cierre de sesión disponible desde app o vía petición POST

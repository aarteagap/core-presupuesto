-- CORE — Control de Presupuesto de Transporte
-- Fase 2: esquema de tarifas vigentes + historial de versiones + Horizon.
-- Ejecutar completo en: Supabase → SQL Editor → New query → Run.
-- Seguro de volver a correr completo (idempotente): las políticas se
-- borran antes de recrearse, así que un segundo Run no falla.

create table if not exists public.tarifa_overrides (
  route_key        text primary key,          -- "PROVEEDOR|||RUTA"
  proveedor        text not null,
  ruta             text not null,
  tarifa_actual    numeric not null,
  pct_adj_nueva    numeric not null,
  fecha_inicio     date not null,
  fecha_vencimiento date not null,
  updated_at       timestamptz not null default now()
);

create table if not exists public.tarifa_overrides_historial (
  id               bigint generated always as identity primary key,
  route_key        text not null,
  proveedor        text not null,
  ruta             text not null,
  tarifa_nueva     numeric not null,
  pct_adj_nueva    numeric not null,
  fecha_inicio     date not null,
  fecha_vencimiento date not null,
  creado_en        timestamptz not null default now()
);

create index if not exists idx_historial_route_key
  on public.tarifa_overrides_historial (route_key, creado_en);

-- RLS: plataforma interna sin login (solo un par de usuarios del área).
-- Se deja lectura/escritura abierta a la anon key, igual que el resto
-- del prototipo. Si más adelante quieres restringir quién escribe,
-- aquí es donde se agregaría una policy más estricta.
alter table public.tarifa_overrides enable row level security;
alter table public.tarifa_overrides_historial enable row level security;

drop policy if exists "anon select overrides" on public.tarifa_overrides;
drop policy if exists "anon upsert overrides" on public.tarifa_overrides;
drop policy if exists "anon update overrides" on public.tarifa_overrides;
create policy "anon select overrides" on public.tarifa_overrides
  for select using (true);
create policy "anon upsert overrides" on public.tarifa_overrides
  for insert with check (true);
create policy "anon update overrides" on public.tarifa_overrides
  for update using (true);

drop policy if exists "anon select historial" on public.tarifa_overrides_historial;
drop policy if exists "anon insert historial" on public.tarifa_overrides_historial;
create policy "anon select historial" on public.tarifa_overrides_historial
  for select using (true);
create policy "anon insert historial" on public.tarifa_overrides_historial
  for insert with check (true);

-- Habilita Realtime para que el Dashboard reciba cambios de tarifa
-- al instante sin recargar (opcional, ya usamos postMessage como
-- respaldo dentro de la misma sesión del navegador). Falla en silencio
-- (con NOTICE, no ERROR) si ya estaba agregada.
do $$ begin
  alter publication supabase_realtime add table public.tarifa_overrides;
exception when duplicate_object then null;
end $$;

-- =====================================================================
-- Fase 2b: FCL de Horizon (despachos), cargado desde el navegador
-- (Maestro → "Cargar Horizon"), sin pasar por ningún backend/API.
-- Reemplaza el bloque fcl_by_week / proyectado_by_week que antes vivía
-- incrustado y fijo dentro del HTML.
-- =====================================================================
create table if not exists public.horizon_fcl (
  proveedor   text not null default '',   -- '' para filas "Proyectado" (sin transportista asignado)
  ruta        text not null,
  pack_plan   integer not null,
  fcl         numeric not null,
  status      text not null check (status in ('confirmado', 'proyectado')),
  updated_at  timestamptz not null default now(),
  primary key (proveedor, ruta, pack_plan, status)
);

alter table public.horizon_fcl enable row level security;

drop policy if exists "anon select horizon_fcl" on public.horizon_fcl;
drop policy if exists "anon upsert horizon_fcl" on public.horizon_fcl;
drop policy if exists "anon update horizon_fcl" on public.horizon_fcl;
drop policy if exists "anon delete horizon_fcl" on public.horizon_fcl;
create policy "anon select horizon_fcl" on public.horizon_fcl
  for select using (true);
create policy "anon upsert horizon_fcl" on public.horizon_fcl
  for insert with check (true);
create policy "anon update horizon_fcl" on public.horizon_fcl
  for update using (true);
create policy "anon delete horizon_fcl" on public.horizon_fcl
  for delete using (true);

do $$ begin
  alter publication supabase_realtime add table public.horizon_fcl;
exception when duplicate_object then null;
end $$;

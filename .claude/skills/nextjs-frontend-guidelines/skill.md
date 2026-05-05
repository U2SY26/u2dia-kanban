---
name: nextjs-frontend-guidelines
description: "Next.js 15 프론트엔드 개발 가이드라인 — U2DIA e-Commerce AI Platform. App Router, Server/Client Components, shadcn/ui, Tailwind CSS 4, Zustand 상태관리, 멀티 테넌트 프론트엔드, Recharts/D3.js 데이터 시각화, 한국어 로컬라이제이션."
---

# Next.js 15 Frontend Development Guidelines — U2DIA e-Commerce AI

## Purpose

U2DIA e-Commerce AI 플랫폼의 프론트엔드 개발 가이드. Next.js 15, React 19 기반.
App Router, Server/Client 컴포넌트 분리, shadcn/ui, Tailwind CSS 4, Zustand 상태관리,
Recharts/D3.js 데이터 시각화, 멀티 테넌트 업체별 커스터마이징 지원.

## When to Use This Skill

- 새 컴포넌트 또는 페이지 생성
- App Router 기반 기능 구현
- Server/Client Components 데이터 페칭
- shadcn/ui + Tailwind CSS 4 스타일링
- API Routes 또는 Server Actions 설정
- 멀티 테넌트 프론트엔드 (업체별 커스터마이징)
- 대시보드/도표/그래프 개발 (Recharts, D3.js)
- Zustand 상태관리
- TypeScript 패턴

---

## Quick Start

### New Component Checklist

- [ ] Server vs Client Component 결정
- [ ] `'use client'` directive 필요시에만 사용
- [ ] Props type → TypeScript interface
- [ ] `@/` import alias 사용
- [ ] shadcn/ui 컴포넌트 활용
- [ ] `cn()` utility로 조건부 클래스
- [ ] Named export
- [ ] Server Components → async 데이터 페칭
- [ ] Client Components → interactivity (useState, useEffect)
- [ ] 한국어 UI 라벨

---

## Project Structure

```
src/
├── app/                        # Next.js App Router
│   ├── page.tsx                # 홈/랜딩 페이지
│   ├── layout.tsx              # Root layout
│   ├── error.tsx               # Error boundary
│   ├── dashboard/              # 대시보드 (protected)
│   │   ├── page.tsx            # 통합 대시보드
│   │   ├── analytics/          # 시장분석/트렌드
│   │   ├── inventory/          # 재고관리
│   │   ├── orders/             # 주문관리
│   │   └── settings/           # 업체 설정
│   ├── admin/                  # 플랫폼 관리자
│   ├── login/                  # 인증
│   ├── tenant/                 # 업체별 커스텀 페이지
│   └── api/                    # API Routes
├── components/
│   ├── ui/                     # shadcn/ui components
│   ├── dashboard/              # 대시보드 컴포넌트
│   ├── charts/                 # Recharts/D3.js 차트
│   ├── inventory/              # 재고 관리 컴포넌트
│   ├── marketplace/            # 마켓플레이스 연동
│   └── layout/                 # 레이아웃 (Navbar, Sidebar 등)
├── lib/                        # Core utilities
│   ├── api.ts                  # API client
│   ├── auth.ts                 # 인증 유틸
│   └── utils.ts                # cn() helper
├── stores/                     # Zustand stores
│   ├── useAuthStore.ts
│   ├── useInventoryStore.ts
│   └── useTenantStore.ts
├── types/                      # TypeScript definitions
├── constants/                  # 상수/Enum
└── middleware.ts               # 라우트 보호, 테넌트 결정
```

---

## Core Patterns

### Server vs Client Components

- **Server Components (default)**: 데이터 페칭, 정적 콘텐츠
- **Client Components ('use client')**: 상태, 이벤트 핸들러, 브라우저 API

### Data Visualization (Recharts/D3.js)

```typescript
'use client';

import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

export function SalesTrendChart({ data }: { data: SalesTrend[] }) {
  return (
    <ResponsiveContainer width="100%" height={400}>
      <LineChart data={data}>
        <CartesianGrid strokeDasharray="3 3" />
        <XAxis dataKey="date" />
        <YAxis />
        <Tooltip />
        <Line type="monotone" dataKey="sales" stroke="#8884d8" />
      </LineChart>
    </ResponsiveContainer>
  );
}
```

### Zustand State Management

```typescript
import { create } from 'zustand';

interface TenantStore {
  tenantId: string | null;
  tenantConfig: TenantConfig | null;
  setTenant: (id: string, config: TenantConfig) => void;
}

export const useTenantStore = create<TenantStore>((set) => ({
  tenantId: null,
  tenantConfig: null,
  setTenant: (id, config) => set({ tenantId: id, tenantConfig: config }),
}));
```

### Multi-Tenant Frontend

```typescript
// middleware.ts — 요청별 테넌트 결정
import { NextRequest, NextResponse } from 'next/server';

export function middleware(request: NextRequest) {
  const tenantId = request.headers.get('x-tenant-id')
    || request.cookies.get('tenant_id')?.value;

  if (tenantId) {
    request.headers.set('x-tenant-id', tenantId);
  }

  return NextResponse.next();
}
```

---

## Import Patterns

| Pattern | Usage | Example |
|---------|-------|---------|
| `@/` | 프로젝트 임포트 | `import { api } from '@/lib/api'` |
| Relative | 같은 디렉토리 | `import { Chart } from './Chart'` |
| `type` | 타입 전용 | `import type { Product } from '@/types'` |

---

## Styling

- shadcn/ui + Tailwind CSS 4
- `cn()` utility로 조건부 클래스 머지
- 반응형: `grid-cols-1 lg:grid-cols-4`
- 한국어 텍스트 기본

---

## Core Principles

1. **Server Components First** — Client Components는 interactivity에만
2. **Recharts/D3.js** — 전문적 도표/그래프 필수
3. **Zustand** — 클라이언트 상태관리
4. **멀티 테넌트** — 업체별 완전 커스터마이징
5. **shadcn/ui** — 일관된 UI 컴포넌트
6. **cn()** — 조건부 클래스 머지 필수
7. **한국어** — 모든 UI 텍스트 한국어
8. **Type Safety** — Strict TypeScript

---

## Resource Guides

| 주제 | 파일 |
|------|------|
| 컴포넌트 패턴 | [resources/component-patterns.md](resources/component-patterns.md) |
| 데이터 페칭 | [resources/data-fetching.md](resources/data-fetching.md) |
| 파일 구조 | [resources/file-organization.md](resources/file-organization.md) |
| 스타일링 | [resources/styling-guide.md](resources/styling-guide.md) |
| 라우팅 | [resources/routing-guide.md](resources/routing-guide.md) |
| 로딩/에러 | [resources/loading-and-error-states.md](resources/loading-and-error-states.md) |
| 성능 최적화 | [resources/performance.md](resources/performance.md) |
| TypeScript | [resources/typescript-standards.md](resources/typescript-standards.md) |
| 공통 패턴 | [resources/common-patterns.md](resources/common-patterns.md) |
| 전체 예제 | [resources/complete-examples.md](resources/complete-examples.md) |

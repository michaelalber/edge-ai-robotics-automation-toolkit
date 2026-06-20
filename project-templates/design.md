# [PROJECT NAME] — Design
<!-- Context Engineering: Design System Reference
     Framework: Four Prompt Disciplines & Five Primitives (Nate B. Jones, v2026.03.2)

     PURPOSE: Agent-readable design system for design-heavy projects.
     Eliminates Figma handoff ambiguity. Export from Stitch, Figma tokens, or
     any design tool. The agent reads this to produce visually consistent output
     without needing access to the design tool itself.

     USE WHEN: The project involves significant UI work, a component library,
     a design system, or any deliverable where visual consistency matters.
     SKIP when: pure backend, CLI tools, or projects with no UI component.

     Copy this template to your project root. Populate from your design tool.
     Delete placeholder comments before committing. -->

---

## Colors

<!-- Export from design tokens. Include both hex and semantic names.
     The agent uses semantic names in code; hex is for verification. -->

### Brand

| Token | Hex | Usage |
|---|---|---|
| `color-brand-primary` | `#______` | Primary actions, links |
| `color-brand-secondary` | `#______` | Secondary actions |
| `color-brand-accent` | `#______` | Highlights, badges |

### Neutral

| Token | Hex | Usage |
|---|---|---|
| `color-neutral-900` | `#______` | Body text |
| `color-neutral-700` | `#______` | Secondary text |
| `color-neutral-400` | `#______` | Placeholder, disabled |
| `color-neutral-100` | `#______` | Backgrounds, dividers |
| `color-neutral-0` | `#ffffff` | White |

### Semantic

| Token | Hex | Usage |
|---|---|---|
| `color-success` | `#______` | Confirmations, success states |
| `color-warning` | `#______` | Warnings, caution states |
| `color-error` | `#______` | Errors, destructive actions |
| `color-info` | `#______` | Informational states |

---

## Typography

### Type Scale

| Token | Size | Line Height | Weight | Usage |
|---|---|---|---|---|
| `text-display` | `__px / __rem` | `___` | `___` | Page titles |
| `text-heading-1` | | | | Section headings |
| `text-heading-2` | | | | Sub-section headings |
| `text-heading-3` | | | | Card/panel headings |
| `text-body-lg` | | | | Primary body text |
| `text-body-md` | | | | Standard body text |
| `text-body-sm` | | | | Supporting text, captions |
| `text-label` | | | | Form labels, badges |
| `text-code` | | | | Code blocks, monospace |

### Font Families

- **Primary (sans-serif):** [e.g., Inter, Segoe UI, system-ui]
- **Secondary (serif):** [e.g., Georgia — for editorial content only]
- **Monospace:** [e.g., JetBrains Mono, Consolas — for code]

---

## Spacing

<!-- Base unit and scale. The agent uses these tokens, not raw pixel values. -->

- **Base unit:** `__px` (e.g., 4px or 8px)
- **Scale:** `4, 8, 12, 16, 24, 32, 48, 64, 96` (adjust to match your system)

| Token | Value | Usage |
|---|---|---|
| `space-1` | `4px` | Tight internal padding |
| `space-2` | `8px` | Default gap between related elements |
| `space-3` | `12px` | |
| `space-4` | `16px` | Default component padding |
| `space-6` | `24px` | Section spacing |
| `space-8` | `32px` | Large section spacing |
| `space-12` | `48px` | Page section breaks |

---

## Borders & Radius

| Token | Value | Usage |
|---|---|---|
| `radius-sm` | `__px` | Buttons, inputs |
| `radius-md` | `__px` | Cards, panels |
| `radius-lg` | `__px` | Modals, drawers |
| `radius-full` | `9999px` | Chips, avatars |
| `border-default` | `1px solid color-neutral-200` | Default borders |

---

## Elevation / Shadow

| Token | Value | Usage |
|---|---|---|
| `shadow-sm` | | Subtle card lift |
| `shadow-md` | | Dropdowns, popovers |
| `shadow-lg` | | Modals, dialogs |

---

## Component Hierarchy

<!-- List the primary UI components this project uses.
     For each: what it is, when to use it, and any usage rules.
     This prevents the agent from inventing inconsistent components. -->

### Buttons

- **Primary** — main CTA per page/section. One per view.
- **Secondary** — supporting actions. Multiple allowed.
- **Destructive** — irreversible actions (delete, remove). Requires confirmation dialog.
- **Ghost / Text** — low-emphasis actions, navigation.
- **Icon** — icon-only actions. Must include accessible aria-label.

### Forms

- **Text Input** — single-line text. Always pair with a `<label>`.
- **Textarea** — multi-line text. Include character count if bounded.
- **Select / Dropdown** — closed option sets. Use autocomplete for >10 options.
- **Checkbox** — multi-select from a list.
- **Radio** — single-select from a small list (≤6 options).
- **Toggle / Switch** — binary setting with immediate effect.
- **Date Picker** — [component name, e.g., Telerik DatePicker]

### Feedback

- **Toast / Snackbar** — transient feedback. Auto-dismiss after 4–6 seconds.
- **Alert / Banner** — persistent feedback requiring action or acknowledgment.
- **Dialog / Modal** — blocking confirmation or complex form.
- **Skeleton Loader** — loading state for content areas.
- **Progress Indicator** — for operations >1 second.

### Navigation

- **Top Nav / App Bar** — global navigation.
- **Side Nav / Drawer** — section navigation.
- **Breadcrumbs** — hierarchical location.
- **Tabs** — peer-level content switching within a view.

---

## Interaction Patterns

<!-- Rules the agent must follow for interactive behavior. -->

- **Loading states:** All async operations ≥300ms must show a loading indicator.
- **Error states:** All form fields must show inline validation errors on blur/submit.
- **Empty states:** All list/table views must have a designed empty state.
- **Confirmation:** Destructive actions require a confirmation dialog with explicit action labeling (not just "OK/Cancel").
- **Accessibility:** All interactive elements must be keyboard-navigable and have visible focus rings.
- **Responsive breakpoints:** `sm: 640px | md: 768px | lg: 1024px | xl: 1280px`

---

## Component Library

<!-- What component library / design system is this project using? -->

- **Library:** [e.g., Telerik UI for Blazor, MudBlazor, shadcn/ui, Radix UI]
- **Version:** [e.g., 6.x]
- **Theme:** [e.g., Default / Custom — see `/wwwroot/css/telerik-theme.css`]
- **Custom components:** [List any bespoke components not from the library]
- **Do not use:** [Any components or patterns explicitly excluded]

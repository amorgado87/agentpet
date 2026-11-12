# AgentPet 🟧

Mascota de escritorio para macOS para tus agentes de código. Hay ocho mascotas pixeladas (robot por defecto, gato, fantasma, perro, caca, ratón, pato y un bicho naranja): caminan por el escritorio, se sube a las ventanas, salta de una a otra, baja al suelo y reaccionan a lo que hacen tus agentes (hoy Claude Code).

> **Aviso**: proyecto no oficial, sin afiliación ni respaldo de Anthropic. «Claude» y «Claude Code» son marcas de sus respectivos propietarios y se mencionan solo para indicar con qué es compatible. Las mascotas son dibujos originales en píxeles.

## Compilar y abrir

Solo necesitas el toolchain de Swift (Command Line Tools), no hace falta Xcode.

```bash
./scripts/build_app.sh
open build/AgentPet.app
```

Aparece un icono en la barra de menús (Ajustes, pausar, modo demo, añadir mascota…). Pruébalo sin agentes: menú → **Modo demo**.

## Qué hace

- **Física**: gravedad, saltos calculados para llegar a otra ventana, rebotes. Puedes agarrar y lanzar a la mascota con el ratón.
- **Ventanas**: usa los bordes superiores de las ventanas visibles como plataformas (ignora las partes tapadas por otras ventanas) y se desplaza con la ventana si la mueves.
- **Claude Code**: detecta los procesos `claude` (terminal y app de escritorio) y lee el final de `~/.claude/projects/**/<sesión>.jsonl` para saber qué hace: pensando, leyendo, buscando, editando (portátil), ejecutando (terminal), planificando, esperando permiso (`!`), terminado (✓)…
- **Varios agentes**: cada sesión tiene su mascota, de un color distinto; los subagentes (`Task`) salen disparados de la mascota madre. Cada una muestra en una burbuja qué está haciendo.
- **Ajustes**: tamaño, color, velocidad, gravedad, comportamiento con ventanas, burbujas, fuentes de agentes, arranque con el sistema, icono en el Dock.

## Estructura (pensada para crecer)

| Archivo | Para qué |
|---|---|
| `Sprite.swift` | Dibujo pixel-art y todas las animaciones (`Visual`). Para otra mascota: otra función de dibujo + paleta. |
| `Models.swift` | `AgentState` / `AgentSnapshot`: vocabulario común. Las mascotas solo conocen esto. |
| `AgentMonitor.swift` | `AgentProvider` (protocolo) + `ClaudeCodeProvider` + `DemoProvider`. **Para Codex u otros: implementar un provider nuevo.** |
| `World.swift` | Suelo y plataformas (ventanas). Es la parte específica de macOS (CoreGraphics). |
| `Pet.swift` | Física y comportamiento de cada mascota. |
| `PetView.swift` | Ventana transparente, burbujas, ratón. |
| `PetManager.swift` | Crea/une/elimina mascotas según los agentes. |
| `SettingsView.swift` | Ventana de ajustes (SwiftUI). |

Herramientas de desarrollo: `AgentPet --sheet out.png` (hoja con todas las animaciones), `--agents` (lista agentes detectados), `--selftest` (simula la física sin pantalla).

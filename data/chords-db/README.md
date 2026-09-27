# chords-db (violão / guitar)

Base de acordes vendorizada de [tombatossals/chords-db](https://github.com/tombatossals/chords-db) para servir de fonte de comparação do motor de identificação de posições de mão.

- **Origem:** https://github.com/tombatossals/chords-db
- **Commit:** `df06fa7b425cf5fd29485ff6591236b3557e3fac` (2025-10-14)
- **Versão do pacote:** 0.6.0
- **Licença:** MIT (ver `LICENSE` neste diretório)
- **Arquivo relevante:** `guitar.json` (extraído de `lib/guitar.json` do pacote já compilado — não precisamos rodar o build em JS)

## Schema de `guitar.json`

```
{
  "main": { "strings": 6, "fretsOnChord": 4, "name": "guitar" },
  "tunings": { "standard": ["E2", "A2", "D3", "G3", "B3", "E4"] },
  "keys": ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"],
  "suffixes": ["major", "minor", "dim", "7", "m7", "sus2", ...],  // 86 no total
  "chords": {
    "C": [
      {
        "key": "C",
        "suffix": "major",
        "positions": [
          {
            "frets": [-1, 3, 2, 0, 1, 0],   // 1 valor por corda, ordem grave->aguda (E A D G B e); -1 = abafada
            "fingers": [0, 3, 2, 0, 1, 0],  // dedo sugerido por corda (0 = não usa dedo/corda solta)
            "baseFret": 1,                  // casa onde o diagrama começa (1 = rastilho)
            "barres": [],                   // casas (relativas ao diagrama) com pestana
            "capo": true,                   // (opcional) presente quando barres.length > 0
            "midi": [48, 52, 55, 60, 64]     // notas MIDI resultantes, grave->aguda
          },
          ...
        ]
      },
      ...
    ],
    "Csharp": [...], "D": [...], ...  // chaves em CamelCase para sustenidos (Csharp = C#, Fsharp = F#)
  }
}
```

**Conversão casa relativa -> casa absoluta no braço:** para `frets[i] > 0`, `casa_absoluta = baseFret - 1 + frets[i]`. Para `baseFret == 1` (posição aberta), `frets[i]` já é a casa absoluta. `-1` sempre significa corda abafada (X), independente do `baseFret`.

**Volume:** 828 combinações chave×sufixo, 3283 posições/voicings ao todo (bem mais amplo que o catálogo curado da versão anterior do Ponteio, que cobria só 7 qualidades). Ainda não filtramos/curamos nada aqui — isso é matéria-prima bruta pra próxima etapa do desenho do algoritmo.

`LICENSE` veio junto por atribuição. O pacote original também tem `piano.json`, `ukulele.json` e `instruments.json` (metadados dos três instrumentos) — nenhum desses foi trazido: o Ponteio, por enquanto, trabalha única e exclusivamente com violão de 6 cordas, então só `guitar.json` faz parte da base.

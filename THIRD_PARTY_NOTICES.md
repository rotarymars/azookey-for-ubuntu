# Third-party notices

ibus-azookey is an **unofficial** Linux port. It is not affiliated with or
endorsed by the azooKey project. It builds on the following components.

| Component | Used as | License |
|---|---|---|
| [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter) | conversion engine (linked) | MIT |
| [azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) | input logic adapted in `Sources/AzooKeyCore/Upstream` and `InputSession.swift` | MIT |
| [azooKey_dictionary_storage](https://github.com/azooKey/azooKey_dictionary_storage) | system dictionary (installed data) | Apache-2.0 |
| [azooKey_emoji_dictionary_storage](https://github.com/azooKey/azooKey_emoji_dictionary_storage) | emoji candidates (installed data) | no license file; see below |
| [zenz-v3.2-small / xsmall](https://huggingface.co/Miwa-Keita/zenz-v3.2-small-gguf) by Miwa Keita | Zenzai model (installed data, unmodified) | Apache-2.0 |
| [llama.cpp](https://github.com/azooKey/llama.cpp) (azooKey fork, tag b4846) | model inference (shared libraries) | MIT |
| [swift-algorithms](https://github.com/apple/swift-algorithms), [swift-collections](https://github.com/apple/swift-collections), [swift-numerics](https://github.com/apple/swift-numerics) | converter dependencies (linked) | Apache-2.0 |
| [swift-tokenizers](https://github.com/ensan-hcl/swift-tokenizers) | converter dependency (linked) | Apache-2.0 |
| [Jinja](https://github.com/johnmai-dev/Jinja) | converter dependency (linked) | MIT |
| [SwiftyMarisa](https://github.com/ensan-hcl/SwiftyMarisa) with marisa-trie | converter dependency (linked) | BSD-2-Clause (dual-licensed with LGPL-2.1+) |
| Swift standard library and Foundation | runtime (linked) | Apache-2.0 with Runtime Library Exception |
| libibus | input method framework (system library) | LGPL-2.1-or-later |

The Apache License 2.0 text is in [data/licenses/Apache-2.0.txt](data/licenses/Apache-2.0.txt)
and is installed next to the dictionary and the model.

**Emoji dictionary:** the azooKey_emoji_dictionary_storage repository has no
license file. It is generated from Mozc's `emoji_data.tsv` (BSD-3-Clause,
Copyright Google Inc.) and Unicode CLDR annotations (Unicode License v3). It is
fetched from upstream at build time; ask the azooKey project before
redistributing binary packages that contain it.

---

## MIT License notices

### AzooKeyKanaKanjiConverter

Copyright (c) 2023 Miwa / Ensan

### azooKey-Desktop

Copyright (c) 2025 Miwa Keita

### llama.cpp / ggml

Copyright (c) 2023-2024 The ggml authors

### Jinja

Copyright (c) 2024 John Mai

The above components are distributed under the following terms:

> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## BSD 2-Clause License notices

### SwiftyMarisa

Copyright (c) 2016, Vladimir Solomenchuk. All rights reserved.

### marisa-trie

Copyright (c) 2010-2019, Susumu Yata. All rights reserved.

> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
> - Redistributions of source code must retain the above copyright notice, this
>   list of conditions and the following disclaimer.
> - Redistributions in binary form must reproduce the above copyright notice,
>   this list of conditions and the following disclaimer in the documentation
>   and/or other materials provided with the distribution.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
> AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
> IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
> DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
> FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
> DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
> SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
> CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
> OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
> OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

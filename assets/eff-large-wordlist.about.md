# eff-large-wordlist.txt — where it came from

The word list rao-chat draws suggested room tokens from
("maple-orbit-velvet-tin"), read by `src/room-folders/007-tokens.lua`.
One word per line, lower-case letters a–z only, no hyphens, sorted, no
repeats.

- **Origin:** the Electronic Frontier Foundation's "EFF large wordlist"
  for passphrases (Joseph Bonneau, 2016), made for dice-rolled passwords:
  every word is common, easy to spell and to say aloud, and no word is a
  prefix-confusion of another.
- **This copy:** taken on 2026-09-25 from KeePassXC's packaged copy on this
  machine, `/usr/share/keepassxc/wordlists/eff_large.wordlist`.  KeePassXC
  ships 7,772 of the EFF's 7,776 words: the four words the EFF list spells
  with a hyphen (such as "t-shirt" and "yo-yo") are left out, which suits
  rao-chat, since it joins words with `-`.
- **Licence:** the EFF publishes its word lists under the Creative Commons
  Attribution 3.0 United States licence (CC BY 3.0 US).  Attribution:
  "EFF large wordlist, Electronic Frontier Foundation,
  https://www.eff.org/dice".
- **Strength:** 7,772 words is log2(7772) ≈ 12.92 bits per word chosen
  uniformly at random.  How many words a suggestion uses is an open choice
  (config key `rooms.suggested-token-words`; see
  `src/room-folders/019-options.lua`).
- **Checking this copy:** `sha256sum assets/eff-large-wordlist.txt` gave
  `df895130803573b14caa684e8cba982a9ed21f4898c98c711f204acf600efedd` when
  it was taken; `tests/010-test-tokens.lua` checks the line count and the
  letters-only rule every run.

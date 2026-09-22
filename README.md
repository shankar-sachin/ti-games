# ti-games

### Brick Blitz — what's in it:

- Angle-based paddle physics (where the ball hits the paddle changes its bounce angle, not just a flat mirror)
- Power-ups: wide paddle, multi-ball, slow-ball, extra life — drop randomly from broken bricks
- Combo scoring — chain hits fast enough and your point multiplier climbs
- Particle bursts + screen shake on brick breaks and deaths, so it actually feels good to play, not just function
- Infinite levels, each one slightly faster and randomized
- Persistent high score — saved via var.store right into the document, survives closing and reopening it

### Game Hub
One Lua file with a menu screen and three games, no exact trademarked names used (called 'em "Tetroid" and "Geo Rush" so nobody's IP lawyers show up at your door):
- Snek Classic — grid snake, wraps at walls, dies if you bite yourself
- Tetroid — 7 pieces, rotation, line clears, gets no faster (I kept gravity simple, tweak tet.speed if you want it brutal)
- Geo Rush — auto-runner, jump with Enter/space, spikes get more frequent and faster over distance

### Loading onto calculator
- Open TI-Nspire Student/Teacher Software (or do it right on the calc, OS 4.0+): Insert → Lua Script
- Paste the whole file in as the script content
- Press play/run, admire your creation, question none of your life choices

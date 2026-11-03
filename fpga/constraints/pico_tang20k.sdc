# J20K — vincoli di tempo del banco video
#
# Solo il clock primario. I derivati — 371,25 MHz dalla rPLL video, 74,25 MHz
# dal CLKDIV, 60,75 MHz dalla rPLL di sistema — Gowin li ricava da se' dai
# parametri delle primitive, ed e' meglio cosi': dichiararli a mano vorrebbe
# dire tenere allineati a mano due posti che dicono la stessa cosa.

create_clock -name sys_clk -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]

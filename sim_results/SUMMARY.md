# Traffic sim: 300 s per run, seeds 1-3, mean of runs

- jam_rate_pct: share of traffic cars stationary for 5 s or more and NOT queued at a red light
- gridlock_pct: share stationary for 20 s or more
- car_contacts_per_min: car-vs-car impacts above 3 m/s

| cars | mode | runs | jam_rate_pct | gridlock_pct | cars_ever_stuck_20s | mean_speed_kmh | intersections_per_car_min | car_contacts_per_min | wrecks |
|---|---|---|---|---|---|---|---|---|---|
| 34 | v1 no signals | 3 | 0.00 | 0.00 | 0.00 | 25.60 | 16.39 | 55.53 | 0.00 |
| 34 | v2 signals | 3 | 1.21 | 0.00 | 0.00 | 11.97 | 8.21 | 0.00 | 0.00 |
| 100 | v1 no signals | 3 | 0.39 | 0.00 | 0.00 | 12.20 | 6.95 | 2254.60 | 0.00 |
| 100 | v2 signals | 3 | 3.19 | 0.32 | 7.00 | 10.33 | 6.97 | 67.80 | 0.00 |
| 160 | v1 no signals | 3 | 0.79 | 0.20 | 4.33 | 8.53 | 4.32 | 3876.47 | 0.00 |
| 160 | v2 signals | 3 | 2.92 | 0.35 | 26.67 | 8.97 | 6.07 | 142.67 | 0.00 |

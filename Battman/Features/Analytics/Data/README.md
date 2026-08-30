# Analytics data boundary

This directory contains immutable metric snapshots, acquisition adapters, and
the visible-card subscription scheduler.

Code in this directory must not import UIKit or construct card views/layers.
Hardware acquisition stays host-owned; public cards receive typed snapshots
through the Analytics lifecycle contract.

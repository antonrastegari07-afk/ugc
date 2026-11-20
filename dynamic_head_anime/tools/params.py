"""Shared shape parameters (units = studs, Blender axes: X = character's left, -Y = front, Z = up)."""
import math
# head: rounded-box superellipsoid, slightly narrower jaw
HA, HB, HC, HN = 0.59, 0.57, 0.60, 3.3          # half width, half depth, half height, exponent
def head_A(z):                                     # half width at height z (bean / jaw taper)
    k = max(0.0, -z / HC)
    return HA * (1 - 0.07 * k * k)
def head_F(x, y, z):
    return abs(x / head_A(z)) ** HN + abs(y / HB) ** HN + abs(z / HC) ** HN
def surf_y(x, z):                                  # front surface depth (negative = front)
    v = 1 - abs(x / head_A(z)) ** HN - abs(z / HC) ** HN
    return -HB * max(v, 0) ** (1 / HN)

# eyes (left eye = +X).  Eye-local u: outward (toward ear), v: up.
EYE_X, EYE_Z = 0.268, -0.035
EYE_A = 0.150                                      # half width of the opening
EYE_TOP, EYE_BOT = 0.040, 0.050                    # half-lidded: low top, round bottom
def eye_top(s):                                    # s in [0,1] inner -> outer corner, returns v
    return EYE_TOP * math.sin(math.pi * s) ** 0.55 * (0.80 + 0.40 * s) - 0.004 * (1 - s)
def eye_bot(s):
    return -EYE_BOT * math.sin(math.pi * s) ** 0.75 * (1.05 - 0.15 * s) - 0.004 * (1 - s)
def eye_u(s):
    return -EYE_A + 2 * EYE_A * s
def eye_world(side, u, v):                         # side=+1 left eye (+X), -1 right eye
    return (side * (EYE_X + u), EYE_Z + v)

# concave eye cup (inverted eyeball -> "follows the camera")
CUP_R = 0.235                                      # sphere radius
CUP_E = 0.075                                      # sphere centre sits this far IN FRONT of the face
CUP_ALPHA = math.radians(50)                       # cap half-angle
CUP_RINGS, CUP_SEGS = 9, 28
LOOK_H, LOOK_V = math.radians(10), math.radians(7)
SOCKET_DEPTH = 0.26                                # cutter depth behind the face at eye centre

# mouth: thin slit with a small smirk (character's left corner up)
MOUTH_Z = -0.285
MOUTH_W = 0.085                                    # half width
MOUTH_GAP = 0.0045                                 # half gap at centre
MOUTH_SMIRK = 0.016
MOUTH_DEPTH = 0.13
def mouth_mid(x):                                  # centre line height
    t = x / MOUTH_W
    return MOUTH_Z + MOUTH_SMIRK * max(0.0, t) ** 2 - 0.004 * t * t
def mouth_half(x):
    t = min(1.0, abs(x) / MOUTH_W)
    return MOUTH_GAP * (1 - t * t) ** 0.7

# brows (texture + bones)
BROW_IN = (0.135, 0.085)     # (x, z) inner end, left side
BROW_OUT = (0.43, 0.115)

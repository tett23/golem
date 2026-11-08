# The figure of figures-external/ with matplotlib (docs/adr/0232):
# 120 by 80 pt, a line, two filled rectangles, two half-transparent
# circles and a word. Run: python3 figure.py OUT.pdf
import sys
import matplotlib
matplotlib.use("pdf")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Rectangle

fig = plt.figure(figsize=(120 / 72, 80 / 72))
ax = fig.add_axes((0, 0, 1, 1))
ax.set_xlim(0, 120)
ax.set_ylim(80, 0)
ax.axis("off")
ax.plot([6, 114], [74, 74], color="#000000", linewidth=2, solid_capstyle="butt")
ax.add_patch(Rectangle((8, 8), 36, 28, facecolor="#ff0000", edgecolor="none"))
ax.add_patch(Rectangle((50, 8), 36, 28, facecolor="#00a0e9", edgecolor="none"))
ax.add_patch(Circle((96, 26), 14, facecolor="#00a000", edgecolor="none", alpha=0.5))
ax.add_patch(Circle((106, 36), 14, facecolor="#0000ff", edgecolor="none", alpha=0.5))
ax.text(8, 62, "Golem", fontsize=16, color="#000000")
fig.savefig(sys.argv[1], metadata={"CreationDate": None})

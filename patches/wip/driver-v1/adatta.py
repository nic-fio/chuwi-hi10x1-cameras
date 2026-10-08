import sys
n = sys.argv[1]
p = f"drivers/media/i2c/{n}.c"
s = open(p).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, (old, s.count(old))
    s = s.replace(old, new)
# firma nuova di set_fmt/get_selection (next, struct v4l2_subdev_client_info)
rep(f"static int {n}_set_format(struct v4l2_subdev *sd,\n",
    f"static int {n}_set_format(struct v4l2_subdev *sd,\n\t\t\t     const struct v4l2_subdev_client_info *ci,\n")
rep(f"static int {n}_get_selection(struct v4l2_subdev *sd,\n",
    f"static int {n}_get_selection(struct v4l2_subdev *sd,\n\t\t\t\tconst struct v4l2_subdev_client_info *ci,\n")
rep(f"return {n}_set_format(sd, state, &fmt);", f"return {n}_set_format(sd, NULL, state, &fmt);")
open(p, "w").write(s)

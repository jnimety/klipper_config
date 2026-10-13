// Ender 3 bed plate (PrusaSlicer's Ender-3 bed model's outline) with the Voron logo cut through its front tab, as on the V0's bedmodel_120x120.stl.
// Regenerate: openscad -o orcaslicer/bed/ender3_bed_voron.stl scripts/ender3_bed_voron.scad
$fn = 64;

// Logo hole loops copied from bedmodel_120x120.stl, re-centered on (0,0).
logo = [
    [[-1.583, -3.75], [3.324, 3.75], [1.583, 3.75], [-3.324, -3.75]],
    [[2.439, 0], [4.179, 0], [1.726, -3.75], [-0.015, -3.75]],
    [[-4.179, 0], [-2.439, 0], [0.015, 3.75], [-1.726, 3.75]],
];

// 240mm plate, r3 corners, plus a trapezoid tab (100mm front edge at Y -135) with r2 fillets.
module plate() {
    offset(r = -2) offset(delta = 2) union() {
        offset(r = 3) square(234, center = true);
        offset(r = 2) offset(delta = -2)
            polygon([[-51.24, -135], [51.24, -135], [63.78, -110], [-63.78, -110]]);
    }
}

difference() {
    translate([0, 0, -3]) linear_extrude(3) plate();
    // Visible strip is Y -135..-117.5: Orca centers the model on the bed, and the 235mm texture leaves
    // 2.5mm of the 240mm body showing in front of the tab. 2x leaves ~1.25mm either side.
    translate([0, -126.25, -5]) scale([2, 2, 1]) linear_extrude(10)
        for (p = logo) polygon(p);
}

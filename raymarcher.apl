⍝  NOTE 
⍝  NOTE  if using without nix you need to manually set these variables
⍝  NOTE 
⍝            png_xres←100 ⋄ png_yres←120
⍝            png_outpath←'lol.png'
⍝            draw_backend←'png'
⍝            drawlib_path←'/nix/store/7hpvv8dd37jiamgp2m1yxgjrkg3gb5m9-apl-raymarcher-drawlib-1.0.0libapl_window_draw_helper.so'
⍝                            ^ path to the .so shared library  for the png/wayland surface helpers


'draw_png'⎕NA (⊃,/{'U4 ' ⍵ '|draw_png  U4 U4 <F4[]'} drawlib_path)
'draw_window'⎕NA (⊃,/{'U4 ' ⍵ '|draw_window  P U4 U4 <F4[]'} drawlib_path)
'init_window_drawer'⎕NA (⊃,/{'P ' ⍵ '|init_window_drawer'} drawlib_path)
'get_res_window'⎕NA (⊃,/{'U4 ' ⍵ '|get_res_window P >U4[2]'} drawlib_path)

⍝ It seems as if conditional ⎕NA (named attribute) definitions aren't possible
⍝ and attempting to do so creates weird issues. So instead i try
⍝ to figure it out at runtime eventhough i don't exactly lik it

drawer_context←{
	⍵≡'wayland': {
		⍝ CHECK IF ⍵=0 for nullptr
		drawer←⍵
		⎕←'m' drawer
		res←↑(get_res_window drawer ( 0 0 ))[2]
		xres←(res)[1] ⋄ yres←(res)[2] 
		xres yres ⍵
	} init_window_drawer
	png_xres png_yres
} draw_backend


xres←drawer_context[1] ⋄ yres←drawer_context[2] 



⍝⎕SE.UCMD 'BOX on'


cam_origin←(0 0 ¯1)

⍝ 2 fields (x,y) for each pixel on the screen
xy←{((⍳(xres))-1)⍵}¨((⍳(yres))-1)

⍝ span uv from 0.0,0.0 to 1.0,1.0
_uv←{(⊃⍵[1]÷xres) (⍵[2]÷yres)}¨xy

⍝ transform uv fro -0.5 to 0.5
uv←_uv-0.5

⍝ apply aspect ratio to uv
uv←{⊃((⍵[1] ÷ (xres ÷ yres)) ⍵[2])}¨uv

uv_vecs ← ⊃,/{y←⍵[2] ⋄ {⍵ (-y)}¨(⊃⍵[1]) }¨uv



epsi←0.0001

⍝ n-th sqrt value
⍝   ⍵ -> value
⍝   ⍵ -> nth-root
sqrt←{⍵*÷⍺}

⍝ vector length
length←{2 sqrt (+/{⍵*2}¨⍵)}

⍝ normalize vector
norm←{o ← ⍵ ⋄ v ← +/{⍵*2}¨o ⋄ w← 2 sqrt v ⋄ {⍵÷w}¨o}

⍝ place cam at 0,0,-1
cam_origin←(0 0 ¯1)



⍝⍺ ->  value to colapm
⍝w -> [ min , max]
clamp←{(⍵[2]) ⌊ ( (⍵[1])⌈⍺ )}


⍝ a -> interpolation factor
⍝ w -> [lower_end upper_end] 
lin_interpol←{
	le←⊃(⍵[1])
	ue←⊃(⍵[2])
	le × ( 1 - ⍺ ) + ue × ⍺
}

⍝ a -> (BROKEN BUT (has a nice effect))
⍝ a -> blend factor
⍝ w[dist1 dist2] sdfs to blend
blend_broken←{
	d_a←⍵[1]
	d_b←⍵[2]
	h← ( 0.5 + 0.5 × ((d_a - d_b)÷⍺)) clamp (0.0 1.0)
	(h lin_interpol d_b (-d_a)) -   ⍺  × h × ( 1.0 - h)
}



⍝ a -> blend factor
⍝ w[dist1 dist2] sdfs to blend
blend←{
	d_a←⊃⊃⍵[1]
	d_b←⊃⊃⍵[2]
	h← ( 0.5 + 0.5 × ((d_b - d_a)÷⍺)) clamp (0.0 1.0)
	(h lin_interpol d_b d_a) -   ⍺  × h × ( 1.0 - h)
}

⍝ a = radius, w = position
ball_sdf←{  (length ⍵) - ⍺ }

⍝ w = p , n , h
inf_plane_floor←{
	((norm ⍺) dot (⊃⍵[1]) ) +  ⊃⍵[2]
}


⍝ a = diameter, w =  position 
octahedron_sdf←{ 0.57735027 × ( {+/(|⍵)} ⍵) - ⍺ }

⍝ ⍵ -> p
⍝ ⍺ ( b , e)
boxframe_sdf←{
	p ← ( (|⍵) - (⊃⍺[1]))
	q ← ((|(p + (⊃⍺[2]))) - (⊃⍺[2]))

	p1←p[1]
	q2←q[2]
	q3←q[3]

	q1←q[1]
	p2←p[2]
	q3←q[3]

	p3←p[3]
	
	u1 ← length ((0 0 0) ⌈ (p1 q2 q3))
	u2 ← length ((0 0 0) ⌈ (q1 p2 q3))
	u3 ← length ((0 0 0) ⌈ (q1 q2 p3))
	

	v1 ← ((0) ⌊ (p1 ⌈ (q2 ⌈ q3)))
	v2 ← ((0) ⌊ (q1 ⌈ (p2 ⌈ q3)))
	v3 ← ((0) ⌊ (q1 ⌈ (q2 ⌈ p3)))

	( u3 + v3 ) ⌊ ((u2 + v2)  ⌊ (u1 + v1))

}

⍝ ⍺  = b(x y z) 
⍝ ⍵ = TODO integrate this with the rounded counterpart below
⍝   to form a single function
⍝ to reduce code duplication
box_sdf←{
	b← ⊃(⍺[1])
	q ← (|⍵) - (b[1])
	(length  ( q ⌈ 0)) +   ( 0 ⌊ (  ( (q[2])  ⌈ (q[3]))  ⌈ (q[1])))
}

⍝ ⍵  = p
⍝ ⍺  = [ b(x y z) , r ]
rounded_box_sdf←{
	b← ⊃(⍺[1])
	r← ⊃(⍺[2])
	q ← (|⍵) - (b[1]) + (r)
	(length  ( q ⌈ 0)) +   ( 0 ⌊ (  ( (q[2])  ⌈ (q[3]))  ⌈ (q[1]))) - (r)
}

torus_sdf←{
	q←((length ( (⍵[1]) (⍵[3]) ))  - (⍺[1]))  (⍵[2])
	(length q) - (⍺[2])
}

scene_obj1_ball←1 
scene_obj2_octa←2
scene_obj3_melted_balls←3
scene_obj4_floor←4
scene_obj5_frame←5
scene_obj6_ball←6
scene_obj7_torus←7
scene_obj8_rounded_box←8
⍝
⍝	TODO TODO TODO TODO when marching it 
⍝ 	is better than not using abs as that wiill add precision
⍝        ((|d)< 0.001 ^ t>max_dist:

⍝ ⍵ ← p
sdf←{
	ball1 ← 0.5 ball_sdf (⍵ - ( 0 ¯1 4) )

	melted_balls2 ← {
		b1←0.5 ball_sdf (⍵ - ( 0.3  1.0 4) )
		b2←0.5 ball_sdf (⍵ - ( 1.55  1.0 4.0) )
		0.8 blend b1 b2
	} (⍵ -  ( 0 ¯0.3 0))

	octa3 ← 0.5 octahedron_sdf ( ⍵ - (  ¯1 0.55 4))

	floor4←⊃(( 0 1 0 ) inf_plane_floor ((⍵ - ( 0 ¯4 0)) 1))

	frame5 ←(( ( 2.0 × 0.65) 0.65 0.65) 0.05 ) boxframe_sdf ( ⍵ - (¯0.65 ¯1 4))

	ball6 ← 0.5 ball_sdf (⍵ - ( ¯1.15 ¯1 4) )

	torus7 ← ( 2.0 0.12) torus_sdf ( ⍵ - ( 0 1.37  4))

	rounded_box8 ←  ( (0.8 1.0 0.8)  0.1 ) rounded_box_sdf  ( ⍵ - ( 0.6 ¯0.5 6.0))

	geo←( ball1 octa3 melted_balls2 floor4 frame5 ball6 torus7 rounded_box8)
	closest←⊃⍋geo

	⍝ dist , which_obj_was_hit
	(geo[closest]) closest

	⍝ ^ deprecated in favor of passing 
	⍝⌊/(a b c)
}

⍝ ⍺ = [ total_dist , ro , rd , max_steps, max_dist ]
⍝ ⍵ = stepcount
march←{
	total_dist ← ⍺[1]
	ro ← ⊃⍺[2] 
	rd ← ⊃⍺[3]
	max_steps ← ⊃⍺[4]
	max_dist ← ⊃⍺[5]

	r ← sdf ( ro + rd × total_dist )

	dist ← r[1]
	obj  ← r[2]

	⍝ if we exceeded the maximum amount of steps return 0
	⍝ AND we exceeded the maximum distance from the ray origin=( eg cam pos/point of reflection) return 0
	
	⍝ TODO use dist to simulate fog  by adding some fog color value based on the distance
	⍵<max_steps ^ dist < max_dist: {
		dist < epsi: (1 (dist + total_dist) obj )
		( (dist + total_dist) ro rd max_steps max_dist) march ⍵
	} ⍵+1
	(0 0)
}


⍝ ⍺ = vector a
⍝ ⍵ = vector b 
dot←{+/(⍵×⍺)}

⍝ ⍺  -> incident vector
⍝ ⍵  -> normal vector
⍝ I - 2.0 * dot(N, I) * N.
reflect←{
	⍺ - 2.0 × ( ⍵ dot ⍺) × ⍵
}

⍝ ⍵ =p
estNormal←{
	e←epsi
	_sdf←{(sdf ⍵)[1]}

	p1←(⍵[1] ×  1.0)
	p2←(⍵[2] ×  1.0)
	p3←(⍵[3] ×  1.0)


	
	a1←p1 p2 p3 + e 0 0
	a2←p1 p2 p3 + 0 e 0 
	a3←p1 p2 p3 + 0 0 e

	b1←p1 p2 p3 - e 0 0
	b2←p1 p2 p3 - 0 e 0 
	b3←p1 p2 p3 - 0 0 e


	s1←(_sdf a1) - (_sdf b1) 
	s2←(_sdf a2) - (_sdf b2) 
	s3←(_sdf a3) - (_sdf b3) 

	norm (s1 s2 s3)
}

⍝ ⍺ = [ ambient_color(rgb), diffuse_color(rgb), specular_color(rgb), alpha, light_intensity ]
⍝ ⍵ = [ p ro ]
phongLight←{
	p←⊃⍵[1]
	ro←⊃⍵[2]

	⍝ TODO REMOVE 0.5 (DEBUG)
	ambient_color←(⊃⍺[1]) × 0.5
	diffuse_factor←⊃⍺[2]
	specular_factor←⊃⍺[3]

	alpha←⊃⍺[4]
	light_intensity←⊃⍺[5]

	⍝ estimate the normal vector at point p on the surface
	n ← estNormal p

	⍝ light position ( TODO don't hardcode up here ) 
	light_pos←((0) (3) (1))

	⍝ vector between the point on the surface and the light position
	l← norm ( light_pos - p)
	⍝ vector between the point on the surface and the view/camera/etc vector
	v← norm ( ro - p)
	⍝ vector  reflecting the light-surface vector on the estimated surfaces normal vector 
	r← norm ( (-l) reflect n )

	⍝ dot product of both
	dotln ← l dot n
	dotrv ← r dot v

	⍝ the light doesn't hit the surface at any relevant angle
	dotln < 0.0: 3 ⍴ 0.0
	
	c ← ambient_color + {
		⍝ angle not in range for specular effect, just apply diffuse color
		⍵ < 0.0: diffuse_factor × dotln
		⍝ angle in range for specular effect, apply diffuse and specular colors
		diffuse_factor × dotln + specular_factor × ( dotrv × alpha )  
	} dotrv 

	light_intensity × c

}

checkers←{
	size←⍺
	pos_x←  ⌊ (  (⍵[1]) ÷ size)
	pos_y← ⌊ (  (⍵[2]) ÷ size)
	3 ⍴ (2.0 | (pos_x + (2.0 | pos_y)))
}

⍝ this is more of a grid tbh
checkers_ball←{
	si←2
	ox←⍵[1]
	oy←⍵[1] + ⍵[2]

	⍝x←(((si○(⍵[1])) + ⍵[2]×50)  | 2.0) > 1.0

	x←( 2.0 | (ox×10) ) > 1.0
	y←(( 2.0 | oy × 10)  ) > 1.0
	x ∨ y : (1 0 0) ⋄ (1 1 1)
}


⍝ ⍵ = [ total_dist , ro , rd , obj]
phong←{
	total_dist←⊃⍵[1]
	ro←⊃⍵[2]
	rd←⊃⍵[3]
	obj←⍵[4]

	p←ro + rd × total_dist


	⍝ TODO some fields lights are mostly a copy of each other
	⍝ specifying them like below really aint the way
	⍝ to go ...
	
	l1←{
		ambient_color←checkers_ball p
		diffuse_color←0.5 0.5 0.5
		specular_color←0.1 0.1 0.1
		alpha←0.7
		light_intensity←⍵

		ambient_color diffuse_color specular_color alpha light_intensity 
	} 0.5

	l2←{
		ambient_color←0.3 0.6 0 
		diffuse_color←0.5 0.5 0.5
		specular_color←0.1 0.9 0.1
		alpha←0.7
		light_intensity←⍵

		ambient_color diffuse_color specular_color alpha light_intensity 
	} 0.5



	l3←{
		ambient_color←(0.0 0.749 1.0) × ( 0.6)
		diffuse_color←ambient_color × ( 0.4)
		specular_color←0.0 0.0 1.0
		alpha←0.7
		light_intensity←⍵

		ambient_color diffuse_color specular_color alpha light_intensity 
	} 1.0

	l4←{
		ambient_color←0.5 0.5 0.5
		diffuse_color←0.5 0.5 0.5
		specular_color←1.0 1.0 1.0
		alpha←0.7
		light_intensity←⍵

		ambient_color diffuse_color specular_color alpha light_intensity 
	} 0.5

	l5←{
		ambient_color←0.57 0.164 0.96
		diffuse_color←0.57 0.164 0.96
		specular_color←0.0 1.0 0.0
		alpha←0.7
		light_intensity←⍵

		ambient_color diffuse_color specular_color alpha light_intensity 
	} 1.0




	l6←{
		ambient_color←0.2 0.2 0.2
		diffuse_color←0.4 0.4 0.4
		specular_color←0.3 0.3 0.3
		alpha←0.7
		light_intensity←⍵

		ambient_color diffuse_color specular_color alpha light_intensity 
	} 0.5


	l7←{
		ambient_color←0.6 0.6 0
		diffuse_color←0.6 0.6 0.0 
		specular_color←1.0 1.0 0.1
		alpha←0.8
		light_intensity←⍵

		ambient_color diffuse_color specular_color alpha light_intensity 
	} 0.7



	⍝ don't hardcode this
	lightPos←3 3 0

	⍝ add ambient colors V 
	{
		⍝ checkered ball
		⍵=scene_obj1_ball: l1 phongLight p ro
		⍝ octahedron
		⍵=scene_obj2_octa: l2 phongLight p ro

		⍝ blob
		⍵=scene_obj3_melted_balls: l3 phongLight p ro

		⍝ floor
		⍵=scene_obj4_floor: (l4 phongLight p ro) + (4 checkers ((p[1]) (p[3])))

		⍵=scene_obj5_frame: (l5 phongLight p ro)

		⍵=scene_obj6_ball: (l6 phongLight p ro) + ( 0.5 × (0.11 checkers ((p[1]) (p[2]))))

		⍵=scene_obj7_torus: (l6 phongLight p ro) + ( 0.5 × (0.22 checkers ((p[1]) (p[2]))))

		⍵=scene_obj8_rounded_box: reflective_material ( p rd ro scene_obj8_rounded_box l7)

	} obj

}

reflective_material←{
	ref_surface_p ← (⊃⍵[1])
	ref_view_rd ← (⊃⍵[2])
	ro ← (⊃⍵[3])
	obj_self← (⊃⍵[4])
	light ← (⊃⍵[5])

    	⍝ normal vector of the point we hit the surface at
	ref_surface_n ← estNormal ref_surface_p

    	⍝ IMPORTANT !!! V
    	⍝ slightly offset the origin to cast the reflected ray from in the direction of the reflecting surfaces
    	⍝ normal vector (which will always point away from it)
	ref_surface_p ← ref_surface_p + ref_surface_n × 0.005

    	⍝ reflect the camera to reflective surface vector using the surfaces normal vector at that position
	ref_reflected_rd ← norm (    ref_view_rd reflect ref_surface_n )


    	⍝ initiate raymarching once more but this time starting from the reflecting surface
    	⍝ using a slightly reduced  step count/max distance
	ref_reflected_final  ← ( 0 ref_surface_p ref_reflected_rd 70 150) march 0

	⍝ 1 if the reflected ray hit anything, otherwise 0 
	hit←(ref_reflected_final[1])
	t←{
		dist←⍵[2]
		obj_is_self← (⍵[3])=obj_self
        	⍝ object intersected with itself ( should never happen for now just color it in a vibrant
        	⍝ green soits easy to debug or maybe throw an exception 
		obj_is_self: ( 0 1 0) 
            		⍝object didn't intersect with itself, apply phong shading at the point the reflection ray hit at
            		phong (dist ref_surface_p ref_reflected_rd (⍵[3]))
	}
	col_obj_self← (light phongLight ref_surface_p  ro )×0.3

    	⍝                      V phong shading at the point the reflection hit at 
	hit: ((t ref_reflected_final)×0.7) + col_obj_self
        	⍝ nothing hit, thus apply background accoring to the reflected vectors orientation
        	((sky (ref_reflected_rd[1])  (0 ⌈((ref_reflected_rd[2])+0.12)))×0.5) + col_obj_self
	⍝ TODO ^ instead of using these hardcoded values allow the user to specify the factor of what
	⍝ rgb components get reflected more and make it bound to distance. For now this is too
	⍝ enhance obj reflecitons while not reflecting the background too much but thats ofc just a hack
}

sky←{
	dawn←(0.4 (0.4 - (2.67 * (⍵[2]  × ¯20.0 )) × 0.15) 0)  × ( 2.67 * ( ⍵[2] × ¯9))
	sky←(0.3 0.5 0.6) × ( 1.0 - (2.67 * (⍵[2] × ¯8.0))) × (2.67 * (⍵[2] ×  ¯0.9))

	⍝ to get the sun wed need the z axis, maybe add it later
	⍝sun←(1.0  0.8 0.55) × (  (0 ⌈ ( (0.0 0.1) dot ⍵) ) * 15.0) × 0.6
	sky+dawn⍝+sun
}

⍝ ⍵ = [ cam_dir time bg ]
rgb←{
	cam_dir←⊃⍵[1]
	time←⊃⍵[2]
	d←(( 0 cam_origin  cam_dir 75 200) march 0)
	hit←d[1]

	⍝ 	phong ( total_dist , ro , rd , obj)

	hit=1: phong ((d[2]) cam_origin cam_dir (d[3]))  

	⍝ If nothing was hit the `sky` function will be called
	⍝ returning the rgb components of the background for the given point

	(sky cam_dir[1] (0 ⌈ ((cam_dir[2])+0.12)))
}


⎕←'rendering @ resolution' xres 'x' yres

s←{
	t←⍵
	pixbuf_rgb←{
		y←⍵[2]
		⍝ cheap progress bar derived from each line drawn
		x←{⍵=-0.5: {⎕←'rendered' (100 + (y+0.5) × -100) '%' ⋄ ⍵}  ⍵ ⋄ ⍵}⍵[1]
		cam_dir←norm x y 1
		(rgb cam_dir t )
	}¨uv_vecs

	draw_backend≡'png': {
		pixbuf_rgb←⊃,/pixbuf_rgb
		⍝⎕←'drawing' (⍴ pixbuf_rgb) 'pixel rgba values (' xres  'x' yres ')=' ( xres × yres ) into '  ⍵
		draw_png xres yres pixbuf_rgb
	}  png_outpath

	draw_backend≡'wayland': {
		pixbuf_rgba←⊃,/{⍵,0}¨pixbuf_rgb
		⎕←drawer_context
		draw_window drawer_context[3] xres yres  pixbuf_rgba

	}¨⍳1 ⍝ for now just draw one frame

} draw_backend

⎕←'press return to quit'
⍞






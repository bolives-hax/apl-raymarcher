⍝ provides methods/operators from the isolate namespace
⍝ which allows us to run compute jobs split across multiple threads/cpu cores 
⍝ or even (in the future) across nodes of a cluster. It also provides
⍝ some helpers for working with futures which will come in handy later
⍝ for example for procedually improving resolution with each sample point
⍝ and other things where an asynchronous mode of operation would offer
⍝ benefits TODO make this optional by supporting the old method
⍝ found in the previous commits
⍝ ⎕LOAD 'isolate' (for now loaded via the nix expression)

⍝  NOTE 
⍝  NOTE  if using without nix you need to manually set these variables
⍝  NOTE 
⍝            png_xres←100 ⋄ png_yres←120
⍝            png_outpath←'lol.png'
⍝            draw_backend←'png'
⍝            drawlib_path←'/nix/store/7hpvv8dd37jiamgp2m1yxgjrkg3gb5m9-apl-raymarcher-drawlib-1.0.0/lib/libapl_window_draw_helper.so'
⍝                            ^ path to the .so shared library  for the png/wayland surface helpers
⍝ variable denoting the number of threads/workers to use. For now
⍝ this needs to either be manually specified / trough the nix drv
⍝ but I plan to read it out trough an environment variable
⍝ also offering the legacy method for systems where isolates (TODO)
⍝ cant be used yet
⍝ threads←4


⍝ TODO respect this by passing it as a C-string from apl to the helper
⍝ for now the image using the png backend will be place into rendering.png
⍝ png_outpath←'lol.png'

⍝ set the max amount of isolates to what the user specified rather
⍝ than forcing it to be equal to the amount of cores. While there isn't
⍝ any point to increasing it past the number of cores I still think
⍝ the user should be able to control it also it can be useful in tests
isolate.Config 'isolates' threads

⍝⍝⍝ obsolete TODO remove though maybe useful for refecence (just for myself)
⍝⍝⍝thread2pix←{thread←(⍵) ⋄ {thread + ((⍵-1)×threads)}¨⍳per_thread}¨⍳threads
⍝⍝⍝thread2pix←{(remainder-⍵) < 0: ⊃(thread2pix[⍵]) ⋄ (⊃(thread2pix[⍵])) ,(xres-remainder-⍵)}¨⍳threads


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

⍝ renderer namespace containing everything specific to the 
⍝ actual rendering process (mostly mathematical primitives/formulas/constants)
⍝ and so on. This is not only cleaner and more flexible if lets say we wanted
⍝ to turn the renderer into a library or define multiple rendering contexts
⍝ but also needed for isolates to split workloads across cores/threads/nodes
⍝ this line creates an empty namespace we then move for example the sqrt function
⍝ into via renderer.sqrt← or renderer.cam_origin to define the camera origin
⍝ TODO also consider moving this into a separte file as its ween that nicely isolated
renderer←⎕NS ''

⍝ couldn't get this to display correctly if run non interactively
⍝⎕SE.UCMD 'BOX on'



⍝ 2 fields (x,y) for each pixel on the screen
xy←{((⍳(xres))-1)⍵}¨((⍳(yres))-1)

⍝ span uv from 0.0,0.0 to 1.0,1.0
_uv←{(⊃⍵[1]÷xres) (⍵[2]÷yres)}¨xy

⍝ transform uv fro -0.5 to 0.5
uv←_uv-0.5

⍝ apply aspect ratio to uv
uv←{⊃((⍵[1] ÷ (xres ÷ yres)) ⍵[2])}¨uv


⍝ n-th sqrt value
⍝   ⍵ -> value
⍝   ⍵ -> nth-root
renderer.sqrt←{⍵*÷⍺}

⍝ vector length
renderer.length←{2 sqrt (+/{⍵*2}¨⍵)}

⍝ normalize vector
renderer.norm←{o ← ⍵ ⋄ v ← +/{⍵*2}¨o ⋄ w← 2 sqrt v ⋄ {⍵÷w}¨o}




⍝⍺ ->  value to colapm
⍝w -> [ min , max]
renderer.clamp←{(⍵[2]) ⌊ ( (⍵[1])⌈⍺ )}


⍝ a -> interpolation factor
⍝ w -> [lower_end upper_end] 
renderer.lin_interpol←{
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
renderer.blend←{
	d_a←⊃⊃⍵[1]
	d_b←⊃⊃⍵[2]
	h← ( 0.5 + 0.5 × ((d_b - d_a)÷⍺)) clamp (0.0 1.0)
	(h lin_interpol d_b d_a) -   ⍺  × h × ( 1.0 - h)
}

⍝ a = radius, w = position
renderer.ball_sdf←{  (length ⍵) - ⍺ }

⍝ w = p , n , h
renderer.inf_plane_floor←{
	((norm ⍺) dot (⊃⍵[1]) ) +  ⊃⍵[2]
}


⍝ a = diameter, w =  position 
renderer.octahedron_sdf←{ 0.57735027 × ( {+/(|⍵)} ⍵) - ⍺ }

⍝ ⍵ -> p
⍝ ⍺ ( b , e)
renderer.boxframe_sdf←{
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
renderer.rounded_box_sdf←{
	b← ⊃(⍺[1])
	r← ⊃(⍺[2])
	q ← (|⍵) - (b[1]) + (r)
	(length  ( q ⌈ 0)) +   ( 0 ⌊ (  ( (q[2])  ⌈ (q[3]))  ⌈ (q[1]))) - (r)
}

renderer.torus_sdf←{
	q←((length ( (⍵[1]) (⍵[3]) ))  - (⍺[1]))  (⍵[2])
	(length q) - (⍺[2])
}

renderer.scene_obj1_ball←1 
renderer.scene_obj2_octa←2
renderer.scene_obj3_melted_balls←3
renderer.scene_obj4_floor←4
renderer.scene_obj5_frame←5
renderer.scene_obj6_ball←6
renderer.scene_obj7_torus←7
renderer.scene_obj8_rounded_box←8
⍝
⍝	TODO TODO TODO TODO when marching it 
⍝ 	is better than not using abs as that wiill add precision
⍝        ((|d)< 0.001 ^ t>max_dist:

⍝ ⍵ ← p
renderer.sdf←{
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
renderer.march←{
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
renderer.dot←{+/(⍵×⍺)}

⍝ ⍺  -> incident vector
⍝ ⍵  -> normal vector
⍝ I - 2.0 * dot(N, I) * N.
renderer.reflect←{
	⍺ - 2.0 × ( ⍵ dot ⍺) × ⍵
}

⍝ ⍵ =p
renderer.estNormal←{
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
renderer.phongLight←{
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

renderer.checkers←{
	size←⍺
	pos_x←  ⌊ (  (⍵[1]) ÷ size)
	pos_y← ⌊ (  (⍵[2]) ÷ size)
	3 ⍴ (2.0 | (pos_x + (2.0 | pos_y)))
}

⍝ this is more of a grid tbh TODO rename
renderer.checkers_ball←{
	si←2
	ox←⍵[1]
	oy←⍵[1] + ⍵[2]

	⍝x←(((si○(⍵[1])) + ⍵[2]×50)  | 2.0) > 1.0

	x←( 2.0 | (ox×10) ) > 1.0
	y←(( 2.0 | oy × 10)  ) > 1.0
	x ∨ y : (1 0 0) ⋄ (1 1 1)
}


⍝ ⍵ = [ total_dist , ro , rd , obj]
renderer.phong←{
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

renderer.reflective_material←{
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
	ref_reflected_final  ← ( 0 ref_surface_p ref_reflected_rd 100 100) march 0

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

renderer.sky←{
	dawn←(0.4 (0.4 - (2.67 * (⍵[2]  × ¯20.0 )) × 0.15) 0)  × ( 2.67 * ( ⍵[2] × ¯9))
	sky←(0.3 0.5 0.6) × ( 1.0 - (2.67 * (⍵[2] × ¯8.0))) × (2.67 * (⍵[2] ×  ¯0.9))

	⍝ to get the sun wed need the z axis, maybe add it later
	⍝sun←(1.0  0.8 0.55) × (  (0 ⌈ ( (0.0 0.1) dot ⍵) ) * 15.0) × 0.6
	sky+dawn⍝+sun
}

⍝ ⍵ = [ cam_dir time bg ]
renderer.rgb←{
	cam_dir←⊃⍵[1]
	time←⊃⍵[2]
	d←(( 0 cam_origin  cam_dir 100 100) march 0)
	hit←d[1]
	⍝
	⍝ 	phong ( total_dist , ro , rd , obj)
	⍝
	hit=1: phong ((d[2]) cam_origin cam_dir (d[3]))  

	⍝ If nothing was hit the `sky` function will be called
	⍝ returning the rgb components of the background for the given point
	⍝
	(sky cam_dir[1] (0 ⌈ ((cam_dir[2])+0.12)))
}

⍝ place cam at 0,0,-1
renderer.cam_origin←(0 0 ¯1)

renderer.epsi←0.0001


⎕←'rendering @ resolution' xres 'x' yres

s←{
	t←⍵

	uv_vecs←⊃,/{y←⍵[2] ⋄ { ⍵ y}¨(⊃⍵[1])}¨uv


	per_thread←⌊((xres×yres)  ÷ threads)

	⍝ TODO covert cases where (xres × yres) ÷ threads
	⍝ is not even by using the variable below and assigning
	⍝ the uneven pixel compute jobs as evenly as possible
	⍝ cause as for now lets say we had a resolution of 11*13=143
	⍝ at 2 or 4 threads wed have 1 remaining pixel we would need
	⍝ to split on one of the 2 workers
	⍝ remainder←(threads | (xres × yres))

	⍝ splits the pixels uv coordinate mappens we calculated
	⍝ above evenly across the threads. In order to make the
	⍝ required functions and variables accessible while keeping
	⍝ everything simple and readable Ive moved the variables into a
	⍝ namespace named renderer which contains all primitives/formulas
	⍝ helpers and constants required for rendering the image
	⍝ As we are instead of moving everything into there (which wouldn't even work
	⍝ for me) moving instead a subset of only the required information contained within 
	⍝ its own namespace has less overhead and also simplifies things a little as now
	⍝ its quite easy to separate everything properly
	⍝
	⍝ TODO account for uneven pixel/thread count
	uv_isolates←{
		threadno←⍵
		⍝ copy th renderer namespace to pass it to the isolate below
		thread_ns←renderer
		thread_ns.per_isolate_uv←{
			⊃(uv_vecs[threadno + ((⍵-1) × threads)])
		}¨⍳per_thread

		ø thread_ns
	}¨⍳threads ⍝ create "threads" number of isolates each equipped with a copy of the renderer
	⍝ namespace which gives access to shared variables/functions and copy the thread-specific
	⍝ uv coordinates into the namespace copy thats respective the the threadno (1 to "threads")

	⍝ run the isolates by putting the uv coordinates we mapped onto the threads above
	⍝ into the rgb function and running that within the isolate context
	⍝ (everything in the "()" round brackets section like the rgb call is actually already run
	⍝ in the isolate using the namespace created/copied above
	⍝ TODO consider outsourcing this  to simplyfy this function call
	⍝ and make it more readable
	piix←uv_isolates.({x←⍵[1] ⋄ y←⍵[2] ⋄ rgb(norm(x (-y) 1) )1}¨per_isolate_uv)


	⍝ after the isolates ran, re need to map the output of the respective isolates
	⍝ pixels back into their order so we essentially apply the reverse from what we applied
	⍝ when we partitioned the uv coordinates for the respective pixels onto the threads/isolates
	pixbuf_rgb←⊃,/{
		pixno←⍵
		{
			thread←⍵
			⊃((⊃(piix[thread]))[pixno])
		}¨⍳threads
	}¨⍳per_thread

	
	draw_backend≡'png': {
		pixbuf_rgb←⊃,/pixbuf_rgb
		⎕←'drawing' (⍴ pixbuf_rgb) 'pixel rgba values (' xres  'x' yres ')=' ( xres × yres ) ' into '  ⍵
		draw_png xres yres pixbuf_rgb
	}  png_outpath

	draw_backend≡'wayland': {
		⍝ the winit library seems to expect pixels in the rgba arrangement unlike the png
		⍝ runner thus we just place a 0 on the end. This would likely be faster if done within
		⍝ the helper directly
		pixbuf_rgba←⊃,/{⍵,0}¨pixbuf_rgb
		⍝ TODO respond to dimension changes and possible allow rendering multiple frames
		⍝⎕←drawer_context
		draw_window drawer_context[3] xres yres  pixbuf_rgba

	}¨⍳1 ⍝ for now just draw one frame

} draw_backend

⎕←'press return to quit'
⍞ ⍝ TODO consider telling the user how long the computation took
⍝ or when using multiple frames maybe even a per-frame statistic so they don't have to perf the command itself
⍝ and remove that line in the end but for the wayland runner the drawing context would close upon APL terminating
⍝ so we have that here





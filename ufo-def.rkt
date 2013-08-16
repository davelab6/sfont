#lang racket

(require "bezier.rkt"
         "vec.rkt"
         "properties.rkt"
         "fontpict.rkt"
         racket/generic
         (planet wmfarr/plt-linalg:1:13/matrix)
         slideshow/pict-convert)

(provide 
 (except-out (all-defined-out)
             position-based-trans
             matrix-based-trans
             compound-based-trans
             clean-arg
             geometric-struct
             apply-glyph-trans))
             
             
             
             
;;; Syntax defintion
;;; The following macros are used to create objects that implement the generic interface gen:geometric
;;; there can be three kinds of behaviour:
;;; 1. position-based (points, anchors, ...)
;;; 2. matrix-based   (components, ...)
;;; 3. compound       (contours)

(define-syntax (position-based-trans stx)
  (syntax-case stx ()
    [(position-based-trans t sup id arg ...)
     #'(define (t o arg ...)
       (struct-copy id o [pos (sup (get-position o) (clean-arg arg) ...)]))]))

(define-syntax (matrix-based-trans stx)
  (syntax-case stx ()
    [(matrix-based-trans t sup id arg ...)
     #'(define (t o arg ...)
       (struct-copy id o [matrix (sup (get-matrix o) (clean-arg arg) ...)]))]))

(define-syntax (compound-based-trans stx)
  (syntax-case stx ()
    [(compound-based-trans field get-field t sup id arg ...)
     #'(define (t o arg ...)
       (struct-copy id o [field (map (lambda (o) (sup o (clean-arg arg) ...))
                                     (get-field o))]))]))

(define-syntax (clean-arg stx)
  (syntax-case stx ()
    [(clean-arg [a d]) #'a]
    [(clean-arg a) #'a]))

(define-syntax-rule (geometric-struct (trans r ...) id expr ...)
  (struct id expr ...
    #:methods gen:geometric
    [(define/generic super-transform transform)
     (define/generic super-translate translate)
     (define/generic super-scale scale)
     (define/generic super-rotate rotate)
     (define/generic super-skew-x skew-x)
     (define/generic super-skew-y skew-y)
     (define/generic super-reflect-x reflect-x)
     (define/generic super-reflect-y reflect-y)
     (trans r ... transform super-transform id m)
     (trans r ... translate super-translate id x y)
     (trans r ... scale super-scale id fx [fy fx])   
     (trans r ... rotate super-rotate id a)
     (trans r ... skew-x super-skew-x id a)
     (trans r ... skew-y super-skew-y id a)
     (trans r ... reflect-x super-reflect-x id)
     (trans r ... reflect-y super-reflect-y id)]))
  
;;;
;;; DATA DEFINITIONS
;;; Font
;;; (font Number Symbol HashTable HashTable String (listOf Layer) HashTable (listOf String) (listOf String))

(struct font 
  (format creator fontinfo groups kerning features layers lib data images)
  #:transparent
  #:property prop:pict-convertible 
  (lambda (f)
    (let ([ascender (dict-ref (font-fontinfo f) 'ascender 750)]
          [descender (dict-ref (font-fontinfo f) 'descender -250)]
          [glyphs (map (lambda (g) (draw-glyph (decompose-glyph f g)))
                       (get-glyphs f *text*))])
      (apply pictf:font ascender descender glyphs))))


;;; Layer
;;; (layer Symbol HashTable HashTable)
;;; Layer can be build from a list of Glyphs or from an HashTable (Name . Glyph)

(struct layer (name info glyphs) 
  #:transparent
  #:guard (lambda (name info glyphs tn)
            (values name
                    info
                    (if (hash? glyphs)
                        (if (immutable? glyphs)
                            glyphs
                            (make-immutable-hash (hash->list glyphs)))
                    (glyphlist->hashglyphs glyphs)))))


;;; Glyph
;;; (glyph Natural Advance (listOf Unicode) String Image (listOf Guideline) 
;;;        (listOf Anchor) (listOf Contour) (listOf Component) HashTable)


(struct glyph (format name advance unicodes note image
                         guidelines anchors contours components lib) 
  #:transparent
  #:property prop:pict-convertible 
  (lambda (g)
    (let* ([cs (map-contours contour->bezier g)]
           [bb (if (null? cs)
                   (cons (vec 0 0) (vec 0 0))
                   (apply combine-bounding-boxes
                          (map bezier-bounding-box cs)))])
      (pictf:glyph (draw-glyph g) bb)))
  #:methods gen:geometric
  [(define/generic super-transform transform)
   (define/generic super-translate translate)
   (define/generic super-scale scale)
   (define/generic super-rotate rotate)
   (define/generic super-skew-x skew-x)
   (define/generic super-skew-y skew-y)
   (define/generic super-reflect-x reflect-x)
   (define/generic super-reflect-y reflect-y)
   (define (transform g m)
     (apply-glyph-trans g super-transform m))
  (define (translate g x y)
    (apply-glyph-trans g super-translate x y))
  (define (scale g fx [fy fx])
    (apply-glyph-trans g super-scale fx fy))
  (define (rotate g a)
    (apply-glyph-trans g super-rotate a))
  (define (skew-x g a)
    (apply-glyph-trans g super-skew-x a))
  (define (skew-y g a)
    (apply-glyph-trans g super-skew-y a))
  (define (reflect-x g)
    (apply-glyph-trans g super-reflect-x))
  (define (reflect-y g)
    (apply-glyph-trans g super-reflect-y))])

; Glyph  (T . ... -> T) . ... -> Glyph
; apply a geometric transformations to a glyph
(define (apply-glyph-trans g fn . args)
  (let ([t (lambda (o) (apply fn o args))])
    (struct-copy glyph g
                 [components (map t (glyph-components g))]
                 [anchors (map t (glyph-anchors g))]
                 [contours (map t (glyph-contours g))])))

;;; Advance
;;; (advance Number Number)
;;; represent the advance width and height of a glyph

(struct advance (width height) #:transparent)

;;; Image
;;; (image String TransformationMatrix Color)

(geometric-struct (matrix-based-trans)
                  image (filename matrix color) 
                  #:transparent
                  #:property prop:has-matrix (lambda (i) (image-matrix i)))

;;; Guideline
;;; (guideline Vec Number String Color Symbol)

(geometric-struct (position-based-trans)
                  guideline (pos angle name color identifier) 
                  #:transparent
                  #:property prop:has-position (lambda (g) (guideline-pos g)))

;;; Anchor
;;; (anchor Vec String Color Symbol)

(geometric-struct (position-based-trans)
                  anchor (pos name color identifier) 
                  #:transparent
                  #:property prop:has-position (lambda (a) (anchor-pos a)))

;;; Contour
;;; (contour Symbol (listOf Point))

(geometric-struct (compound-based-trans points contour-points) 
                  contour (identifier points) 
                  #:transparent)

;;; Component
;;; (component Symbol TransformationMatrix Symbol)

(geometric-struct (matrix-based-trans)
                  component (base matrix identifier) 
                  #:transparent
                  #:property prop:has-matrix (lambda (c) (component-matrix c)))

;;; Point
;;; (point Vec Symbol Boolean String Symbol)
;;;
;;; Point-type can be one of
;;; - curve
;;; - offcurve
;;; - qcurve
;;; - line
;;; - move


(geometric-struct (position-based-trans)
                  point (pos type smooth name identifier) 
                  #:transparent
                  #:property prop:has-position (lambda (p) (point-pos p)))

;(struct point (pos type smooth name identifier) 
;  #:transparent
;   #:property prop:has-position point-pos
;  #:property prop:transform 
;  (lambda (v m) (point-transform v m)))

;;; Color
;;; (list Number Number Number Number)
;;; the four number represent:
;;; Red     [0, 1]
;;; Green   [0, 1]
;;; Blue    [0, 1]
;;; Alpha   [0, 1]

; Number Number Number Number -> Color
; produce a color
(define (color r g b a)
  (list r g b a))

;;; Unicode
;;; Unicode is a Number



; (listOf Glyphs) -> (hashTableOf Glyphs)
; produce an immutable hashtable where keys are the names of glyphs and values are the glyphs
(define (glyphlist->hashglyphs gs)
  (make-immutable-hash 
   (map (lambda (g) (cons (glyph-name g) g))
        gs)))


; (hashTableOf Glyphs) -> (listOf Glyphs)
; produce a list of glyphs from hashtables of glyphs
(define (hashglyphs->glyphlist gh)
  (hash-values gh))

; Font [Symbol] -> Layer or False
(define (get-layer f [layer 'public.default])
  (findf (lambda (l) (eq? (layer-name l) layer))
         (font-layers f)))

; (Layer -> T) Font -> (listOf T)
; apply the procedure to each layer, collect the results in a list 
(define (map-layers proc f)
  (map proc (font-layers f)))

; (Layer -> T) Font -> side effects
; apply the procedure to each layer
(define (for-each-layer proc f)
  (for-each proc (font-layers f)))

; (Glyph -> Boolean) -> (listOf Glyphs)
; filter the list of glyphs in the layer with the procedure
(define (filter-glyphs proc layer)
  (filter proc (layer-glyphs layer)))

; Font Layer -> Font
; produce a new font with the layer added (or updated if a layer with the same name already exists)
(define (set-layer f new-layer)
  (let ((layers (font-layers f))
        (new-name (layer-name new-layer)))
    (struct-copy font f
                 [layers
                  (dict-values
                   (dict-set (map-layers 
                              (lambda (l) (cons (layer-name l) l)) f)
                             new-name new-layer))])))


; Font Symbol [Symbol] -> Glyph or False
; Return the given Glyph in the given Layer, Layer defaults to 'public.default
(define (get-glyph f g [l 'public.default])
  (let ([la (get-layer f l)])
    (if la
        (hash-ref (layer-glyphs la) g #f)
        (error "get-glyph: layer does not exist"))))


; Font (listOf Symbol) [Symbol] -> (listOf Glyph)
; Return the given Glyphs in the given Layer, Layer defaults to 'public.default
(define (get-glyphs f gs [l 'public.default])
  (filter identity
          (map (lambda (g) (get-glyph f g l)) gs)))
        
; Font Symbol [Symbol] -> Font
; produce a new font with the glyph removed from the given layer
(define (remove-glyph f g [layername 'public.default])
  (let ((l (get-layer f layername)))
    (set-layer f (struct-copy layer l 
                              [glyphs (hash-remove (layer-glyphs l) g)]))))
    
; Font Glyph [Symbol] -> Font
; produce a new font with the glyph inserted in the given layer
(define (insert-glyph f g [layername 'public.default])
  (let ((l (get-layer f layername)))
    (set-layer f (struct-copy layer l 
                              [glyphs (hash-set (layer-glyphs l)
                                                (glyph-name g)                                                              
                                                g)]))))
                     
; Font Symbol -> (listOf (Symbol . Glyph))
; produce a list of pairs whose first member is the name of the layer
; and the second element is the glyph g in that layer
(define (get-layers-glyph font g)
  (map-layers 
   (lambda (l) 
     (let ([name (layer-name l)])
       (cons name (get-glyph font g name))))
   font))
  
; (Glyph -> T) (Font or Layer) [Symbol] Boolean -> (listOf T)
; apply the procedure to each glyph in the layer, collects the result in a list
; If o is a font, it will select the layer passed named
; If Sorted is true the function will be applied to a sorted (alphabetically) list of glyphs
(define (map-glyphs proc o [l 'public.default] #:sorted [sorted #f])
  (let ([la (cond [(font? o) (get-layer o l)]
                  [(layer? o ) o]
                  [else (error "map-glyphs: first argument should be a layer or a font")])])
    (if la
        (map proc (if sorted
                      (sort-glyph-list (hash-values (layer-glyphs la)))
                      (hash-values (layer-glyphs la))))
        (error "map-glyphs: layer does not exist"))))

; (Glyph -> T) (Font or Layer) [Symbol] Boolean -> side effects
; apply the procedure to each glyph in the layer
; If o is a font, it will select the layer passed named
; If Sorted is true the function will be applied to a sorted (alphabetically) list of glyphs
(define (for-each-glyph proc o [layer 'public.default] #:sorted [sorted #f])
  (let ([l (cond [(font? o) (get-layer o layer)]
                 [(layer? o ) o]
                 [else (error "for-each-glyphs: first argument should be a layer or a font")])])
    (if l
        (for-each proc (if sorted
                           (sort-glyph-list (hash-values (layer-glyphs l)))
                           (hash-values (layer-glyphs ))))
        (error "for-each-glyph: layer does not exist"))))

; Font -> (listOf Symbol)
; produce a list of glyph names present in the font 
(define (glyphs-in-font f)
  (set->list
    (foldl set-union
           (set)
           (map-layers 
            (lambda (l) 
              (list->set (map-glyphs glyph-name f (layer-name l))))
            f))))

; (listOf Glyph) (Glyph -> T) (T T -> Boolean) -> (listOf Glyph)
; produce a sorted list of glyphs
(define (sort-glyph-list gl 
                         #:key [key (lambda (g) (symbol->string (glyph-name g)))]
                         #:pred [pred string<?])
  (sort gl #:key key pred))



; (Number -> Number) Kernings -> Kernings
; apply the procedure to every kerning value, produce a new kerning table
(define (map-kerning proc k)
  (make-immutable-hash
   (hash-map k (lambda (l kr)
                 (cons l 
                       (make-immutable-hash
                        (hash-map kr (lambda (r v) (cons r (proc v))))))))))


; Font -> Font
; produce a new font that try to be compatible with ufo2 specs
(define (font->ufo2 f)
  (struct-copy font f [format 2] [data #f] [images #f]
               [layers (list 
                        (layer 'public.default #f 
                               (map-glyphs glyph->glyph1 f)))]))
; Font -> Font
; produce a new font that try to be compatible with ufo3 spec     
(define (font->ufo3 f) 
  (struct-copy font f [format 3]
               [layers (map-layers
                        (lambda (l)
                          (struct-copy layer l
                                       [glyphs (map-glyphs glyph->glyph2 f (layer-name l))]))
                        f)]))


; Font Glyph [Symbol] -> Glyph
; decompose glyph components to outlines
(define (decompose-glyph f g [ln 'public.default])
  (define (decompose-base c)
    (decompose-glyph f (get-glyph f (component-base c) ln) ln))
  (let* ([cs (glyph-components g)])
    (if (null? cs)
        g
        (let* ([bases (map decompose-base cs)]
               [dcs (apply append (map component->outlines cs bases))])
          (struct-copy glyph g
                       [components null]
                       [contours (append (glyph-contours g) dcs)])))))

; Font Symbol -> Layer
; produces a new layer with glyphs decomposed
(define (decompose-layer f [ln 'public.default])
  (struct-copy layer (get-layer f ln)
               [glyphs (map-glyphs (lambda (g) 
                                     (decompose-glyph f g ln))
                        f ln)]))

; Font Glyph Symbol Boolean -> BoundingBox
; produces the Bounding Box for the given glyph
(define (glyph-bounding-box f g [ln 'public.default] [components #t])
  (let* ([g (if components 
                (decompose-glyph f g ln)
                g)]
         [cs (glyph-contours g)])
    (if (null? cs)
        (cons (vec 0 0) (vec 0 0))
        (apply combine-bounding-boxes 
               (map (lambda (c) 
                      (bezier-bounding-box (contour->bezier c)))
                    cs)))))


; Font Symbol Boolean -> BoundingBox
; produces the Bounding Box for the given font
(define (font-bounding-box f [ln 'public.default] [components #t])
  (apply combine-bounding-boxes
         (map-glyphs (lambda (g) (glyph-bounding-box f g ln components))
                     f)))


 
; Font Glyph Symbol -> (Number . Number)
; produce a pair representing the left and right sidebearings for the given glyph
(define (sidebearings f g [ln 'public.default])
  (let* ([bb (glyph-bounding-box f g ln)]
         [a (advance-width (glyph-advance g))])
    (if (equal? bb (cons (vec 0 0) (vec 0 0)))
        #f
        (cons (vec-x (car bb))
              (- a (vec-x (cdr bb)))))))

 
; Font Glyph Number Symbol -> (listOf Vec)
; produce a list of the intersections of outlines with the line y = h
(define (intersections-at f g h [ln 'public.default])
  (let* ([g (decompose-glyph f g ln)]
         [cs (glyph-contours g)])
    (sort 
     (remove-duplicates
      (apply append 
             (map (lambda (c) 
                    (bezier-intersect-hor h (contour->bezier c)))
                  cs))
      vec=)
     < #:key vec-x)))


; Font Glyph Number Symbol -> (Number . Number)
; produce a pair representing sidebearings measured at y = h
(define (sidebearings-at f g h [ln 'public.default])
  (let* ([is (intersections-at f g h)]
         [a (advance-width (glyph-advance g))])
    (if (null? is)
        #f
        (cons (vec-x (car is)) (- a (vec-x (last is)))))))
    
  

; Font Glyph Symbol -> Number
; produces the area for the given glyph (negative if in the wrong direction)
(define (glyph-signed-area f g [ln 'public.default])
  (let* ([g (decompose-glyph f g ln)]
         [cs (glyph-contours g)])
    (foldl + 0 
           (map (lambda (c) 
                  (bezier-signed-area (contour->bezier c)))
                cs))))


; Font Glyph Number Number Symbol -> Glyph
; set left and right sidebearings for the glyph 
(define (set-sidebearings f g left right [ln 'public.default])
  (let* ([os (sidebearings f g ln)]
         [oa (advance-width (glyph-advance g))])     
    (if os
        (let* ([la (- left (car os))]
               [ra (+ la (- right (cdr os)))])
          (struct-copy glyph 
                       (translate g la 0)
                       [advance (advance (+ oa ra)
                                         (advance-height 
                                          (glyph-advance g)))]))
        #f)))
                       
     

; Font Glyph Number Number Number Symbol -> Glyph
; set left and right sidebearings (measured at y = h) for the glyph 
(define (set-sidebearings-at f g left right h [ln 'public.default])
  (let* ([os (sidebearings-at f g h ln)]
         [oa (advance-width (glyph-advance g))])     
    (if os
        (let* ([la (- left (car os))]
               [ra (+ la (- right (cdr os)))])
          (struct-copy glyph 
                       (translate g la 0)
                       [advance (advance (+ oa ra)
                                             (advance-height 
                                              (glyph-advance g)))]))
        #f)))


; Font Glyph Number Number Symbol -> Glyph
; adjust left and right sidebearings for the glyph
(define (adjust-sidebearings f g left right [ln 'public.default])
  (let* ([os (sidebearings f g ln)])     
    (if os
        (set-sidebearings f 
                          g 
                          (+ (car os) left) 
                          (+ (cdr os) right)
                          ln)
        g)))


; Font -> Font
; produces a new font with contour in the correct direction
(define (correct-directions f)
  (struct-copy font f
               [layers 
                (map-layers 
                 (lambda (l)
                   (struct-copy layer l
                                [glyphs 
                                 (map-glyphs 
                                  glyph-correct-directions
                                  f (layer-name l))]))
                 f)]))

        

; Font Symbol -> side effects
; Print the glyph           
(define (print-glyph f gn)
  (let* ([g (decompose-glyph f (get-glyph f gn))]
         [ascender (hash-ref (font-fontinfo f) 'ascender 750)]
         [upm (hash-ref (font-fontinfo f) 'unitsPerEm 1000)]
         [cs (map-contours contour->bezier g)]
         [bb (if (null? cs)
                 (cons (vec 0 0) (vec 0 0))
                 (apply combine-bounding-boxes
                        (map bezier-bounding-box cs)))])
      (pictf:glyph (draw-glyph g) bb ascender upm)))
                     
; Font -> Font
; Round the coordinates of the font using the current *precision* factor
(define (font-round f)
  (struct-copy font f
               [layers (map-layers layer-round f)]
               [kerning (kerning-round (font-kerning f))]))

; Layer -> Layer
; Round the coordinates of the layer using the current *precision* factor
(define (layer-round l)
  (struct-copy layer l
               [glyphs (map-glyphs glyph-round l)]))

; kerning -> kerning
; Round the kerning values using the current *precision* factor
(define (kerning-round k)
  (map-kerning approx k))

; Glyph -> Glyph
; Round the coordinates of the glyph using the current *precision* factor
(define (glyph-round g)
  (struct-copy glyph g
               [advance (advance-round (glyph-advance g))]
               [image (if (glyph-image g)
                          (image-round (glyph-image g))
                          #f)]
               [guidelines (map guideline-round (glyph-guidelines g))]
               [anchors (map anchor-round (glyph-anchors g))]
               [contours (map contour-round (glyph-contours g))]
               [components (map component-round (glyph-components g))]))

; Advance -> Advance
; Round the coordinates of the advance using the current *precision* factor
(define (advance-round a)
  (struct-copy advance a 
               [width (approx (advance-width a))]
               [height (approx (advance-height a))]))

; Image -> Image
; Round the coordinates of the image using the current *precision* factor
(define (image-round i)
  (struct-copy image i
               [matrix (struct-copy trans-mat (image-matrix i))]))
                       
; Guideline -> Guideline
; Round the coordinates of the guideline using the current *precision* factor
(define (guideline-round g)
  (struct-copy guideline g 
               [pos (struct-copy vec (guideline-pos g))]))

; Anchor -> Anchor
; Round the coordinates of the anchor using the current *precision* factor
(define (anchor-round a)
  (struct-copy anchor a 
               [pos (struct-copy vec (anchor-pos a))]))

; Contour -> Contour
; Round the coordinates of the contour using the current *precision* factor
(define (contour-round c)
  (struct-copy contour c 
               [points (map point-round (contour-points c))]))

; Component -> Component
; Round the coordinates of the component using the current *precision* factor
(define (component-round c)
  (struct-copy component c 
               [matrix (struct-copy trans-mat (component-matrix c))]))

; Point -> Point
; Round the coordinates of the point using the current *precision* factor
(define (point-round p)
  (struct-copy point p 
               [pos (struct-copy vec (point-pos p))]))

; (String or Number) -> Number
; produce a number from a string or return the number
(define (ensure-number n)
  (if (or (not n) (number? n)) n (string->number n)))

; (String or Symbol) -> Symbol
; produce a symbol from a string or return the symbol
(define (ensure-symbol s)
  (if s
      (if (symbol? s) s (string->symbol s))
      s))

; ("yes" or "no" or Boolean) -> Boolean
; produce a boolean from yes/no strings or return the boolean
(define (ensure-smooth s)
  (match s
    [#f #f]
    ["no" #f]
    [#t #t]
    ["yes" #t]))

; String -> Color
; produce a color from a string of the type "r,g,b,a"
(define (string->color s)
  (apply color
         (map (lambda (s) (string->number (string-trim s))) 
              (string-split s ","))))

; Color -> String
; produce a string of type "r,g,b,a" from a color
(define (color->string c)
  (string-join (map number->string c) ","))

; (String or Color) -> Color
; produce a color from the string or return the color
(define (ensure-color c)
  (if (string? c) (string->color c) c))

; String -> Unicode
; produce an Unicode from String
(define (string->unicode s)
  (string->number (string-append "#x" s)))

; Unicode -> String 
; produce a String from an Unicode
(define (unicode->string n)
  (~r n #:base '(up 16) #:pad-string "0" #:min-width 4))

;;; The following procedures are used for reading glyph from a glif file but they can be useful for other reasons.

(define (make-advance #:width [width 0] #:height [height 0])
  (advance (ensure-number width) (ensure-number height)))

(define (make-image #:fileName [filename #f] #:xScale [x-scale 1] #:xyScale [xy-scale 0] 
                        #:yxScale [yx-scale 0] #:yScale [y-scale 0] #:xOffset [x-offset 0]
                        #:yOffset [y-offset 0] #:color [color #f])
  (image filename (trans-mat (ensure-number x-scale) (ensure-number xy-scale) 
                             (ensure-number yx-scale) (ensure-number y-scale) 
                             (ensure-number x-offset) (ensure-number y-offset))
         (ensure-color color)))


(define (make-guideline #:x [x #f] #:y [y #f]  #:angle [angle #f] 
                            #:name [name #f] #:color [color #f] 
                            #:identifier [identifier #f])
  (guideline (vec (ensure-number x) (ensure-number y)) (ensure-number angle) name (ensure-color color) (ensure-symbol identifier)))

(define (make-anchor #:x [x #f] #:y [y #f] #:name [name #f] 
                         #:color [color #f] #:identifier [identifier #f])
  (anchor (vec (ensure-number x) (ensure-number y)) name (ensure-color color) (ensure-symbol identifier)))

(define (make-contour #:identifier [identifier #f] #:points [points null])
  (contour (ensure-symbol identifier) points))

(define (make-component #:base [base #f]  #:xScale [x-scale 1] #:xyScale [xy-scale 0] 
                        #:yxScale [yx-scale 0] #:yScale [y-scale 1] #:xOffset [x-offset 0]
                        #:yOffset [y-offset 0] #:identifier [identifier #f])
  (component (ensure-symbol base) 
             (trans-mat (ensure-number x-scale) (ensure-number xy-scale) 
                        (ensure-number yx-scale) (ensure-number y-scale) 
                        (ensure-number x-offset) (ensure-number y-offset))
             (ensure-symbol identifier)))

(define (make-point #:x [x #f] #:y [y #f] #:type [type 'offcurve] 
                        #:smooth [smooth #f] #:name [name #f] #:identifier [identifier #f])
  (point (vec (ensure-number x) (ensure-number y)) (ensure-symbol type)
             (ensure-smooth smooth) name (ensure-symbol identifier)))

; (Contour -> T) Glyph -> (listOf T)
; apply the procedure to each contour of the glyph, collect results in a list
(define (map-contours proc g)
  (map proc (glyph-contours g)))

; (Contour -> T) Glyph -> side effects
; apply the procedure to each contour of the glyph
(define (for-each-contours proc g)
  (for-each proc (glyph-contours g)))

; (Component -> T) Glyph -> (listOf T)
; apply the procedure to each component of the glyph, collect results in a list
(define (map-components proc g)
  (map proc (glyph-components g)))

; (Component -> T) Glyph -> side effects
; apply the procedure to each component of the glyph
(define (for-each-components proc g)
  (for-each proc (glyph-components g)))

; (Guideline -> T) Glyph -> (listOf T)
; apply the procedure to each guideline of the glyph, collect results in a list
(define (map-guidelines proc g)
  (map proc (glyph-guidelines g)))

; (Guideline -> T) Glyph -> side effects
; apply the procedure to each guideline of the glyph
(define (for-each-guidelines proc g)
  (for-each proc (glyph-guidelines g)))

; (Anchor -> T) Glyph -> (listOf T)
; apply the procedure to each anchor of the glyph, collect results in a list
(define (map-anchors proc g)
  (map proc (glyph-anchors g)))

; (Anchor -> T) Glyph -> side effects
; apply the procedure to each anchor of the glyph
(define (for-each-anchors proc g)
  (for-each proc (glyph-anchors g)))

; (Point -> T) Contour -> (listOf T)
; apply the procedure to each point of the contour, collect results in a list
(define (map-points proc c)
  (map proc (contour-points c)))

; (Point -> T) Contour -> side effects
; apply the procedure to each point of the contour
(define (for-each-points proc c)
  (for-each proc (contour-points c)))

; Glyph -> DrawableGlyph
; produce a printable version of the glyph
(define (draw-glyph g)
  (append (list (glyph-name g)
                (advance-width (glyph-advance g)))
          (map-contours contour->bezier g)))

; Contour -> DrawableContour
; produce a printable version of the contour
(define (draw-contour c)
  (letrec ((aux (lambda (pts)
                  (match pts
                    [(list-rest (point _ 'offcurve _ _ _) rest-points)
                     (aux (append rest-points (list (car pts))))]
                     [_ pts]))))
    (draw-points (aux (contour-points c)))))

; (listOf Point) -> (listOf DrawablePoint)
; produce a printable version of the points
(define (draw-points pts)
  (let* ((first-pt (car pts))
         (rest-pts (cdr pts))
         (start (vec->list (point-pos first-pt))))
    (cons (cons 'move start)
          (append (map (lambda (pt)
                         (match pt 
                           [(point (vec x y) 'offcurve _ _ _)
                            `(off ,x ,y)]
                           [(point (vec x y) _ _ _ _)
                            `(,x ,y)]))
                       rest-pts)
                  (list start)))))

; Glyph -> Glyph
; Produce a new glyph hat try to be compatible with glif1 specs
(define (glyph->glyph1 g)
  (match g
    [(glyph format name advance (list codes ...) note image 
                guidelines anchors contours components lib)
     (glyph 1 name advance codes #f #f null null 
                (append 
                 (map (lambda (c) 
                       (match c
                         [(contour _ points)
                          (contour 
                           #f (map (lambda (p) 
                                     (struct-copy point p [identifier #f]))
                                   points))]))
                       contours)
                 (map anchor->contour anchors))
                (map (lambda (c) 
                       (struct-copy component c [identifier #f]))
                       components)
                lib)]))

; Glyph -> Glyph
; Produce a new glyph hat try to be compatible with glif2 specs
(define (glyph->glyph2 g)
  (struct-copy glyph g [format 2]))

; Anchor -> Contour
; produce a contour with one point only that is used by convention in Glif1 to define an anchor
(define (anchor->contour a)
  (make-contour #:points (list (make-point #:x (vec-x (anchor-pos a))
                                           #:y (vec-y (anchor-pos a))
                                           #:name (anchor-name a)
                                           #:type 'move))))



; Contour -> Bezier
; Transform a contour in a bezier curve (i.e. all segments are made by 4 points)
(define (contour->bezier c)
  (letrec ((ensure-first-on-curve 
            (lambda (pts)
              (match pts
                [(list-rest (point _ 'move _ _ _) pr) pts]
                [(list-rest (point _ 'curve _ _ _) pr) pts]
                [(list-rest (point _ 'line _ _ _) pr) pts]
                [(list-rest (point _ 'qcurve _ _ _) pr) pts]
                [(list-rest (point _ 'offcurve _ _ _) pr) 
                 (ensure-first-on-curve (append pr (list (car pts))))])))
           (flattener 
            (lambda (pts acc)
              (match pts
                [(list-rest (or
                             (point v 'curve _ _ _)
                             (point v 'move _ _ _)
                             (point v 'line _ _ _))
                            (point v1 'line _ _ _)
                            _)
                 (flattener (cdr pts) (append acc (list v v v1)))]
                [(list-rest (point v 'offcurve _ _ _) pr)
                 (flattener pr (append acc (list v)))]
                [(list-rest (point v 'curve _ _ _) pr)
                 (flattener pr (append acc (list v)))]
                [(list-rest (point v 'move _ _ _) pr)
                 (flattener pr (append acc (list v)))]
                [(list-rest (point v 'line _ _ _) pr)
                 (flattener pr (append acc (list v)))]
                [(list) acc]))))
    (let* ((points (ensure-first-on-curve (contour-points c)))
           (first-point (car points)))
      (if (eq? (point-type first-point) 'move)
          (flattener points '())
          (flattener (append points (list first-point)) '())))))


; Bezier -> Contour
; Transform a bezier curve in a contour 
(define (bezier->contour b)
  (letrec ((aux 
            (lambda (prev pts acc)
              (match (cons prev pts)
                [(list-rest (vec x y) (vec x y) (vec x2 y2) (vec x2 y2) rest-pts)
                   (aux (vec x2 y2) rest-pts (append acc (list (make-point #:x x2 #:y y2 #:type 'line))))]
                [(list-rest (vec x y) (vec ox1 oy1) (vec ox2 oy2) (vec x2 y2) rest-pts)
                 (aux (vec x2 y2) rest-pts (append acc
                                                  (list (make-point #:x ox1 #:y oy1)
                                                        (make-point #:x ox2 #:y oy2)
                                                        (make-point #:x x2 #:y y2 #:type 'curve))))]
                [(list _) acc]
                [(list) null]))))
    (let* ((first-pt (car b))
           (ufo-pts (aux first-pt (cdr b) null)))
      (make-contour #:points 
                        (if (closed? b) ufo-pts
                            (cons (make-point #:x (vec-x first-pt)
                                              #:y (vec-y first-pt)
                                              #:type 'move)
                                  ufo-pts))))))
   


; Component Glyph -> (listOf Contour)
; produce a list of contours from a component applying the trasformation matrix to the contours in the base
(define (component->outlines c b)
  (let ([m (component-matrix c)]
        [base-contours (glyph-contours b)])
    (map (lambda (c) (transform c m))
         base-contours)))
     



; Contour -> Boolean
; True if the contour starts with a point of type 'move
(define (contour-open? c)
  (eq? 'move (point-type (car (contour-points c)))))


; Contour -> Contour
; returns the contour with reversed point list
(define (reverse-contour c)
  (if (contour-open? c)
      c
      (struct-copy contour c
                   [points (contour-points 
                            (bezier->contour 
                             (reverse (contour->bezier c))))])))


; Glyph -> Glyph
; reverse the direction of all contours in the glyph
(define (glyph-reverse-directions g)
  (struct-copy glyph g 
               [contours (map reverse-contour 
                              (glyph-contours g))]))


; Glyph -> Glyph
; reverse the direction of all contours in the glyph if the area is negative
(define (glyph-correct-directions g)
  (let* ([cs (map-contours (lambda (c) (map-points point-pos c)) g)]
         [a (foldl (lambda (b acc) 
                     (+ acc (bezier-signed-area b)))
                   0 cs)])
    (if (< a 0)
        (glyph-reverse-directions g)
        g)))


#;
(define (glyph-correct-directions g)
  (let* ([cs (map contour->bezier (glyph-contours g))]
         [a (foldl (lambda (b acc) 
                     (+ acc (bezier-signed-area b)))
                   0 cs)])
    (if (< a 0)
        (struct-copy glyph g 
                     [contours (map (lambda (c b)
                                      (struct-copy contour c
                                                   [points (contour-points (bezier->contour (reverse b)))]))
                                    (glyph-contours g) cs)])
        g)))
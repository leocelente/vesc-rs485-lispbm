(define rs485-id "0")
(define rs485-broadcast-id "*")

(uart-start 115200)
;; UART Byte time
(define uart-byte-time 100); Testing showed stable system with a 100us byte-time
(define uart-buf (array-create 100))

;; Smallest timestep (s)
(define dt 0.010)
;; Microsecond delay between steps
(define delay (to-i (* dt 1000000)))


(defun parse (buffer)
    (let (  (tokens    (str-split buffer " "))  )
        (if (> (length tokens) 1)
            (let (  (id              (first tokens))
                    (is-correct-id   (= 0 (str-cmp id rs485-id)))
                    (is-broadcast-id (= 0 (str-cmp id rs485-broadcast-id)))
                    (cmd-and-args    (rest tokens))
                    (cmd             (first cmd-and-args))
                    (args            (rest cmd-and-args))
                )
                (cond 
                    (is-correct-id (trimmed-write 
                                (str-merge rs485-id " " (dispatch cmd args) "\n" )))
                    (is-broadcast-id (dispatch cmd args))
                    (t (print "INCORRECT_ID")) 
                )             
            )
        )
    )
)

(defun dispatch (cmd args)
    (cond
        ((= 0 (str-cmp cmd "duty"))            (cmd-duty args))
        ((= 0 (str-cmp cmd "d"))               (cmd-duty args))
        ((= 0 (str-cmp cmd "encoder"))         (cmd-encoder args))
        ((= 0 (str-cmp cmd "e"))               (cmd-encoder args))
        ((= 0 (str-cmp cmd "reset_encoder"))   (cmd-reset-encoder args))
        ((= 0 (str-cmp cmd "r"))               (cmd-reset-encoder args))
        ((= 0 (str-cmp cmd "temp_motor"))      (cmd-temp-motor args))
        ((= 0 (str-cmp cmd "temp_mosfet"))     (cmd-temp-mosfet args))
        ((= 0 (str-cmp cmd "temp"))            (cmd-temp args))
        ((= 0 (str-cmp cmd "t"))               (cmd-temp args))
        ((= 0 (str-cmp cmd "rate"))            (cmd-set-rate args))
        (t                                     "CMD_NOT_FOUND")
    )
)

(defun commands-thread () 
    (loopwhile t
        (progn
            (uart-read-until uart-buf (buflen uart-buf) 0 10) ; 10 is the \n
            (bufclear uart-buf 0 (- (str-len uart-buf) 1) ) ; remove newline
            (parse uart-buf)
        )
    )
)

(define setpoint 0.0)
(define rate 0.02)

(defun duty-cycle-mask (desired) 
    (cond
        ((< (abs desired) 0.1) 0.0)
        ((> (abs desired) 0.8) (* 0.8 (sign desired)))
        (t desired)
    )
)

(defun sign (x) (if (>= x 0) 1 -1))

(defun duty-cycle-thread ()
    (let ((virtual (get-duty))) ; thread local variable
        (loopwhile t
            (let (  (distance (- setpoint virtual))
                    (up-down (sign distance))
                )
                (progn
                    (if (> (abs distance) 0.01) ; set threshold to avoid oscillating or set to 0
                        (progn 
                            (setvar 'virtual (+ virtual (* rate up-down)))
                            (set-duty (duty-cycle-mask virtual))
                            (print "UPDATE DUTY:" virtual (duty-cycle-mask virtual) "-")
                        )
                    )
                    (yield delay)    
                )
            )    
        )
    )
)

(defun float-to-str (f) (str-from-n f "%.3f"))

(defun cmd-encoder (args) (float-to-str (get-encoder)) )
(defun cmd-reset-encoder (args) (progn (set-encoder 0.0) (cmd-encoder)) )
(defun cmd-temp-mosfet (args) (float-to-str (get-temp-fet)))
(defun cmd-temp-motor (args) (float-to-str (get-temp-mot)))
(defun cmd-temp (args) (str-merge (cmd-temp-motor) "," (cmd-temp-mosfet)))
(defun cmd-set-rate (args) (progn (define rate (str-to-f (first args))) (float-to-str rate)))
(defun cmd-set-delay (args)(progn (define dt (str-to-f (first args))) (define delay (to-i (* dt 1000000)))
 (float-to-str rate)))

(defun calculate-time (setpoint)
    (let ( (delta-duty (- setpoint (get-duty))) 
           (steps (to-i (/ delta-duty rate))) 
           (delta-time (* steps dt))
         ) 
         (float-to-str delta-time)
    )
)
(defun cmd-duty (args) 
    (progn
        (define setpoint (str-to-f (first args)))
        (calculate-time setpoint)
    )
)

(define commands-thread-id   (spawn-trap 512 commands-thread))
(define dutycycle-thread-id (spawn-trap 512 duty-cycle-thread))

(defun thread-monitor ()
      (recv  ((exit-error (? tid) (? e)) 
        (progn 
            (print "Restarting thread:" tid e)
            (print uart-buf)
            (cond 
                ((= tid commands-thread-id)  
                            (define commands-thread-id (spawn-trap 512 commands-thread)))
                ((= tid dutycycle-thread-id)  
                            (define dutycycle-thread-id (spawn-trap 512 duty-cycle-thread)))
                (t (print "Unknown Thread Failed:" tid e ))
            )
            (thread-monitor)
        ))
        ((exit-ok (? tid) (? v)) (print "Thread exited" tid))
    )            
)

(defun trimmed-write (buffer) 
    (let ( (buffer-trimmed (array-create (str-len buffer))) ) 
        (progn 
            (gpio-write 'pin-rs485re 1) 
            (gpio-write 'pin-rs485de 1) 
            (bufcpy buffer-trimmed 0 buffer 0 (str-len buffer))
            (uart-write buffer-trimmed)
            (yield (* uart-byte-time (buflen buffer-trimmed)))         
            (gpio-write 'pin-rs485de 0) 
            (gpio-write 'pin-rs485re 0) 
        )        
    )
)


(thread-monitor)

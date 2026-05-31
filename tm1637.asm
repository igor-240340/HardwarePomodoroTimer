;
; tm1637.asm - библиотека для взаимодействия с 7-сегментным дисплеем на базе TM1637.

            .EQU CLK_PIN = 2                                ; CLK - на PB2.
            .EQU DIO_PIN = 3                                ; DIO - на PB3.

            .EQU COLON = 0x80                               ; Бит двоеточия. Двоеточие привязано ко второму разряду (индекс 1).

            ;
            ; Команды дисплея.
            .EQU CMD_DISP = 0x80                            ; Код команды управления дисплеем.
            .EQU CMD_DATA = 0x40                            ; Код команды управления передачей данных.
            .EQU CMD_ADDR = 0xC0                            ; Код команды установки регистра адреса.

            ;
            ; Параметры дисплея.
            .EQU DISP_ON = 0x08                             ; Дисплей включен.
            .EQU BRGHT_7 = 0x07                             ; Максимальная яркость.
            .EQU BRGHT_4 = 0x04                             ;
            .EQU BRGHT_2 = 0x02                             ;
            .EQU BRGHT_1 = 0x01                             ;
            .EQU BRGHT_0 = 0x00                             ; Минимальная яркость.
            .EQU POS_MAX = 0x03                             ; Максимальная позиция.
            .EQU DISP_PRESET7 = (DISP_ON | BRGHT_7)         ; Включить дисплей, яркость на максимум.
            .EQU DISP_PRESET4 = (DISP_ON | BRGHT_4)         ; Включить дисплей, яркость на 4.
            .EQU DISP_PRESET2 = (DISP_ON | BRGHT_2)         ; Включить дисплей, яркость на 2.
            .EQU DISP_PRESET1 = (DISP_ON | BRGHT_1)         ; Включить дисплей, яркость на 1.
            .EQU DISP_PRESET0 = (DISP_ON | BRGHT_0)         ; Включить дисплей, яркость на минимум.

            ;
            ; Параметры передачи данных.
            .EQU ADDR_INC = 0x00                            ; Автоматический инкремент.
            .EQU ADDR_FIXED = 0x04                          ; Фиксированный адрес.

            ;
            ; Задержка 5us при 1.2MHz (9.6MHz + предделитель на 8).
.MACRO DELAY5US
            NOP
            NOP
            NOP
            NOP
            NOP
            NOP
.ENDM

            ;
            ; Инициализировать дисплей.
INIT_DISP:  SBI DDRB, CLK_PIN                               ; CLK = DIO = 0.
            SBI DDRB, DIO_PIN                               ;
            CBI PORTB, CLK_PIN                              ;
            CBI PORTB, DIO_PIN                              ;

            LDI R16, (CMD_DISP | DISP_PRESET1)              ;
            MOV ARG1, R16                                   ;
            RCALL I2CSTART                                  ;
            RCALL SENDBYTE                                  ;
            RCALL I2CSTOP                                   ;

            RET                                             ;

            ;
            ; Отобразить цифру в указанном разряде.
            ;
            ; Вход:
            ; - ARG1: Код цифры.
            ; - ARG2: Номер разряда.
SHOW_DIGIT: MOV R16, ARG1                                   ; Копируем код цифры.
            MOV R17, ARG2                                   ; Копируем номер разряда.

            LDI ARG1, (CMD_DATA | ADDR_FIXED)               ; Настраиваем фиксированную адресацию.
            PUSH_R16R17                                     ; Бэкапим код цифры и номер разряда.
            RCALL I2CSTART                                  ;
            RCALL SENDBYTE                                  ;
            RCALL I2CSTOP                                   ;

            POP R17                                         ; Восстанавливаем номер разряда.
            LDI ARG1, CMD_ADDR                              ; Добавляем в команду номер разряда.
            OR ARG1, R17                                    ;
            RCALL I2CSTART                                  ;
            RCALL SENDBYTE                                  ; Код цифры уже в стеке, а номер разряда нам больше не нужен.
            
            POP R16                                         ; Восстанавливаем код цифры.
            MOV ARG1, R16                                   ; Передаём код цифры.
            RCALL SENDBYTE                                  ;
            RCALL I2CSTOP                                   ;

            RET                                             ;

            ;
            ; Очистить дисплей.
CLEARDISP:  LDI R16, 3                                      ; Индекс разряда.
            LDI R17, 4                                      ; Счетчик разрядов.
CLEARDISP1: LDI ARG1, 0x00                                  ; Гасим все сегменты в текущем разряде.
            MOV ARG2, R16                                   ;
            PUSH_R16R17                                     ;
            RCALL SHOW_DIGIT                                ;
            POP_R17R16                                      ;
            DEC R16                                         ; Уменьшаем индекс разряда.
            DEC R17                                         ; Уменьшаем счётчик разядов.
            BRNE CLEARDISP1                                 ; Очистили все разряды?
            RET                                             ; Да.

            ;
            ; Зажигает все сегменты во всех разрядах.
LIGHTALL:   LDI R16, 3                                      ; Индекс разряда.
            LDI R17, 4                                      ; Счетчик разрядов.
LIGHTALL1:  LDI ARG1, 0xFF                                  ; Зажигаем все сегменты в текущем разряде.
            MOV ARG2, R16                                   ;
            PUSH_R16R17                                     ;
            RCALL SHOW_DIGIT                                ;
            POP_R17R16                                      ;
            DEC R16                                         ; Уменьшаем индекс разряда.
            DEC R17                                         ; Уменьшаем счётчик разядов.
            BRNE LIGHTALL1                                  ; Прошлись по всем разрядам?
            RET                                             ; Да.

            ;
            ; Передать байт.
            ;
            ; Вход:
            ; - ARG1: Команда/данные.
SENDBYTE:   MOV R16, ARG1                                   ; Копируем байт команды/данных.

            LDI R17, 8                                      ; Количество передаваемых бит.
SENDBYTE1:  CBI PORTB, CLK_PIN                              ; CLK = 0.
            DELAY5US                                        ;

            ROR R16                                         ; Извлекаем бит данных в бит переноса.
            BRCC ZERO                                       ; Бит данных нулевой?
            SBI PORTB, DIO_PIN                              ; Нет, выставляем 1 на DIO.
            RJMP SENDBYTE2                                  ;
ZERO:       CBI PORTB, DIO_PIN                              ; Да, выставляем 0 на DIO.
SENDBYTE2:  SBI PORTB, CLK_PIN                              ; CLK = 1.
            DELAY5US                                        ;
            DEC R17                                         ; Передали все биты команды?
            BRNE SENDBYTE1                                  ; Нет, продолжаем.   
            CBI PORTB, CLK_PIN                              ; Да. CLK = 0.
            CBI DDRB, DIO_PIN                               ; DIO = 1 (release).
            SBI PORTB, DIO_PIN                              ;
            DELAY5US                                        ;

            ; Ожидание ACK.
            IN R16, PINB                                    ; Читаем DIO.
            SBRC R16, DIO_PIN                               ; DIO == 0?
            RJMP SENDBYTE4                                  ; Нет.
            RJMP SENDBYTE3                                  ; Да.
SENDBYTE4:  SBI DDRB, DIO_PIN                               ; DIO = 0.
            CBI PORTB, DIO_PIN                              ;
SENDBYTE3:  DELAY5US                                        ;
            
            SBI PORTB, CLK_PIN                              ; CLK = 1.
            DELAY5US                                        ;

            CBI PORTB, CLK_PIN                              ; CLK = 0.
            DELAY5US                                        ;

            SBI DDRB, DIO_PIN                               ;

            RET                                             ;

            ;
            ; Инициировать передачу данных.
I2CSTART:   SBI PORTB, DIO_PIN                              ; DIO = 1.
            SBI PORTB, CLK_PIN                              ; CLK = 1.
            DELAY5US                                        ;
            CBI PORTB, DIO_PIN                              ; DIO = 0.
            RET                                             ;

            ;
            ; Завершить передачу данных.
I2CSTOP:    CBI PORTB, CLK_PIN                              ; CLK = 0.
            DELAY5US                                        ;

            CBI PORTB, DIO_PIN                              ; DIO = 0.
            DELAY5US                                        ;

            SBI PORTB, CLK_PIN                              ; CLK = 1.
            DELAY5US                                        ;

            SBI PORTB, DIO_PIN                              ; DIO = 1.
            RET                                             ;

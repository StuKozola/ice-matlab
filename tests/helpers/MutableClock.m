classdef MutableClock < handle
    %MutableClock Tiny handle wrapper so anonymous funcs can read mutable time.
    properties
        Now (1,1) double = 0
    end
    methods
        function v = read(obj)
            v = obj.Now;
        end
    end
end

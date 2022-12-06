
return feature("hello", {
    entry = function(self, ...)
        stderr("Hello world!, you did pass those arguments: " + array(pack(...)):join_tostring(", "))
    end
})